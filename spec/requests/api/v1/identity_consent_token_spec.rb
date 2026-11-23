# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Identity with consent_token", type: :request, real_auth: true do
  include ActiveSupport::Testing::TimeHelpers

  let!(:partner) { create(:partner, :approved, raw_api_key: "test_api_key") }
  let(:headers)  { { "X-Partner-Api-Key" => "test_api_key", "Content-Type" => "application/json" } }

  let!(:citizen)    { create(:user, :with_address, bonid: "BZ-1970-M-ND-P2334-0B6") }
  let!(:submission) { create(:identity_submission, :approved, user: citizen) }

  def approved_consent(type, scopes: %w[profile])
    TransactionConsent.create!(citizen: citizen, partner: partner, transaction_type: type, scopes: scopes).tap do |c|
      c.update_columns(status: TransactionConsent.statuses[:approved], decided_at: Time.current)
    end
  end

  def fetch(consent)
    get "/api/v1/identity/#{citizen.bonid}", params: { consent_token: consent.consent_token }, headers: headers
  end

  context "money movement (one-time token)" do
    let(:consent) { approved_consent("wire_transfer") }

    it "returns the data once, then refuses the token" do
      fetch(consent)
      expect(response).to have_http_status(:ok)

      fetch(consent)
      expect(response).to have_http_status(:gone)
      expect(JSON.parse(response.body)["error"]).to match(/consumed/)
    end
  end

  context "identity check (reusable within the window)" do
    let(:consent) { approved_consent("kyc_check") }

    it "can be read more than once inside 10 minutes" do
      2.times do
        fetch(consent)
        expect(response).to have_http_status(:ok)
      end
    end

    it "is refused after the 10-minute window" do
      consent
      travel_to(11.minutes.from_now) do
        fetch(consent)
        expect(response).not_to have_http_status(:ok)
      end
    end
  end

  context "address scope" do
    address_keys = %w[address department commune street_address locality
                      communal_section arrondissement postal_code country]

    it "returns every address part from the citizen's profile when address is approved" do
      fetch(approved_consent("kyc_check", scopes: %w[profile address]))
      expect(response).to have_http_status(:ok)

      identity = JSON.parse(response.body)["identity"]
      expect(identity).to include(
        "street_address"   => "123 Rue Test",
        "locality"         => "Port-au-Prince",
        "communal_section" => "1re Section Test",
        "commune"          => "Port-au-Prince",
        "arrondissement"   => "Port-au-Prince",
        "department"       => "Ouest",
        "postal_code"      => "HT6000",
        "country"          => "Haiti"
      )
      expect(identity["address"]).to include("HT6000")
    end

    it "returns no address part when address is not approved" do
      fetch(approved_consent("kyc_check", scopes: %w[profile]))
      expect(response).to have_http_status(:ok)

      identity = JSON.parse(response.body)["identity"]
      expect(identity.keys & address_keys).to be_empty
    end
  end

  context "verification and biometrics" do
    it "never sends the reviewer's name, and hides both biometrics blocks without identity:verify" do
      # account_opening adds no implicit scopes (kyc_check would add identity:verify)
      fetch(approved_consent("account_opening", scopes: %w[profile]))
      expect(response).to have_http_status(:ok)

      identity = JSON.parse(response.body)["identity"]
      expect(identity).to have_key("verification")
      expect(identity["verification"]).not_to have_key("verified_by")
      expect(identity["verification"]["reference"]).to eq(submission.uuid)
      expect(identity).not_to have_key("biometrics")
      expect(identity).not_to have_key("biometric_verification")
    end

    it "returns both biometrics blocks with identity:verify, still without the reviewer's name" do
      submission.update!(metadata: (submission.metadata || {}).merge(
        "liveness"   => { "passed" => true, "confidence" => 98.4 },
        "face_match" => { "status" => "match", "similarity" => 96.1 }
      ))

      fetch(approved_consent("account_opening", scopes: %w[profile identity:verify]))
      expect(response).to have_http_status(:ok)

      identity = JSON.parse(response.body)["identity"]
      expect(identity["verification"]).not_to have_key("verified_by")
      expect(identity).to have_key("biometrics")
      expect(identity["biometric_verification"]).to include("liveness_passed" => true, "face_matched" => true)
    end
  end
end
