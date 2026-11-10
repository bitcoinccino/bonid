# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Identity with consent_token", type: :request, real_auth: true do
  include ActiveSupport::Testing::TimeHelpers

  let!(:partner) { create(:partner, :approved, raw_api_key: "test_api_key") }
  let(:headers)  { { "X-Partner-Api-Key" => "test_api_key", "Content-Type" => "application/json" } }

  let!(:citizen)    { create(:user, :with_address, bonid: "BZ-1970-M-ND-P2334-0B6") }
  let!(:submission) { create(:identity_submission, :approved, user: citizen) }

  def approved_consent(type)
    TransactionConsent.create!(citizen: citizen, partner: partner, transaction_type: type, scopes: %w[profile]).tap do |c|
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
end
