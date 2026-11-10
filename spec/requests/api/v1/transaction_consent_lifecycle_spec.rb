# frozen_string_literal: true

require "rails_helper"

# End-to-end consent lifecycle for EVERY transaction type the API accepts,
# with a citizen whose identity is verified right now:
#   partner requests → citizen approves (code, or face check) →
#   partner sees "approved" → partner fetches only the approved details.
#
# The test citizen is fictional. Never put a real BonID here: its P####
# segment is the last 4 digits of the person's CIN.
RSpec.describe "Transaction consent lifecycle", type: :request, real_auth: true do
  include ActiveSupport::Testing::TimeHelpers

  OTP = "246810"

  # Partners are limited to their sector's types by default (a bank gets the
  # banking types). Grant every type so all of them can be exercised here.
  let!(:partner) do
    create(:partner, :approved, raw_api_key: "test_api_key").tap do |p|
      p.update_column(:allowed_transaction_types, TransactionConsent::VALID_TRANSACTION_TYPES)
    end
  end
  let(:api)      { { "X-Partner-Api-Key" => "test_api_key", "Content-Type" => "application/json" } }

  let!(:davidson) do
    create(:user, :with_address, :identity_verified,
           first_name: "Davidson", last_name: "Louis", bonid: "DL-1990-M-OU-P0000-TST")
  end

  before do
    # Capture the code the citizen would receive by email/SMS
    allow(TransactionConsentService).to receive(:generate_otp).and_return(OTP)
  end

  def request_consent(type)
    body = { bonid: davidson.bonid, transaction_type: type, scopes: %w[profile] }
    body[:amount] = 100 if TransactionConsent::MONEY_MOVEMENT_TYPES.include?(type)
    post "/api/v1/transaction_consents", params: body.to_json, headers: api
    expect(response).to have_http_status(:created), "#{type}: create returned #{response.status} #{response.body}"
    JSON.parse(response.body)["consent_token"]
  end

  def partner_sees_status(token)
    get "/api/v1/transaction_consents/#{token}", headers: api
    JSON.parse(response.body)["status"]
  end

  def fetch_identity(token)
    get "/api/v1/identity/#{davidson.bonid}", params: { consent_token: token }, headers: api
  end

  def expect_approved_details_once_or_reusable(type, token)
    fetch_identity(token)
    expect(response).to have_http_status(:ok), "#{type}: fetch returned #{response.status} #{response.body}"
    identity = JSON.parse(response.body)["identity"]
    expect(identity["first_name"]).to eq("Davidson"), "#{type}: approved profile not returned"
    expect(identity).not_to have_key("email"), "#{type}: returned a detail the citizen didn't approve"

    fetch_identity(token)
    if TransactionConsent::MONEY_MOVEMENT_TYPES.include?(type)
      expect(response).to have_http_status(:gone), "#{type}: one-time token was reusable"
    else
      expect(response).to have_http_status(:ok), "#{type}: reusable token was refused"
    end
  end

  describe "approving with the 6-digit code" do
    TransactionConsent::VALID_TRANSACTION_TYPES.each do |type|
      it "works end to end for #{type}" do
        token = request_consent(type)

        post "/api/v1/transaction_consents/#{token}/decide",
             params: { otp: OTP, decision: "approve" }.to_json,
             headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:ok), "#{type}: decide returned #{response.status} #{response.body}"

        expect(partner_sees_status(token)).to eq("approved")
        expect_approved_details_once_or_reusable(type, token)
      end
    end
  end

  describe "approving with the face check" do
    let(:liveness_session) { "6e183b42-a256-45b1-af0c-1b7d4c5761ae" }

    before do
      sign_in davidson
      # AWS liveness is external; simulate a passed check.
      allow(FaceLivenessService).to receive(:get_results)
        .and_return({ success: true, passed: true, confidence: 99.4 })
    end

    TransactionConsent::VALID_TRANSACTION_TYPES.each do |type|
      it "works end to end for #{type}" do
        token = request_consent(type)

        post "/citizens/transaction_consents/#{token}/liveness_decide",
             params: { liveness_session_id: liveness_session }
        consent = TransactionConsent.find_by(consent_token: token)
        expect(consent).to be_approved, "#{type}: face-check approval didn't go through (#{response.status})"
        expect(consent.biometric_verified_at).to be_present
        expect(consent.liveness_confidence.to_f).to eq(99.4)

        expect(partner_sees_status(token)).to eq("approved")
        expect_approved_details_once_or_reusable(type, token)
      end
    end
  end

  describe "citizens whose identity isn't verified right now" do
    it "refuses a request for a BonID with no approved identity" do
      unverified = create(:user, bonid: "UV-1990-M-OU-P0000-TST")
      post "/api/v1/transaction_consents",
           params: { bonid: unverified.bonid, transaction_type: "wire_transfer", scopes: %w[profile] }.to_json, headers: api
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["reason"]).to eq("bonid_not_verified")
    end

    it "refuses a request once the identity has expired" do
      davidson.identity_submissions.update_all(expires_at: 1.day.ago)
      post "/api/v1/transaction_consents",
           params: { bonid: davidson.bonid, transaction_type: "wire_transfer", scopes: %w[profile] }.to_json, headers: api
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a request once the identity is revoked (e.g. name-change suspension)" do
      davidson.identity_submissions.update_all(status: IdentitySubmission.statuses[:revoked])
      post "/api/v1/transaction_consents",
           params: { bonid: davidson.bonid, transaction_type: "wire_transfer", scopes: %w[profile] }.to_json, headers: api
      expect(response).to have_http_status(:forbidden)
    end

    it "blocks approval if the identity is revoked after the request was sent, but still allows declining" do
      token = request_consent("wire_transfer")
      davidson.identity_submissions.update_all(status: IdentitySubmission.statuses[:revoked])

      post "/api/v1/transaction_consents/#{token}/decide",
           params: { otp: OTP, decision: "approve" }.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:forbidden)
      expect(partner_sees_status(token)).to eq("pending")

      post "/api/v1/transaction_consents/#{token}/decide",
           params: { otp: OTP, decision: "deny" }.to_json, headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(partner_sees_status(token)).to eq("denied")
    end

    it "blocks face-check approval once the identity has expired" do
      token = request_consent("wire_transfer")
      davidson.identity_submissions.update_all(expires_at: 1.minute.ago)
      sign_in davidson
      allow(FaceLivenessService).to receive(:get_results).and_return({ success: true, passed: true, confidence: 99.4 })

      post "/citizens/transaction_consents/#{token}/liveness_decide",
           params: { liveness_session_id: "6e183b42-a256-45b1-af0c-1b7d4c5761ae" }
      expect(TransactionConsent.find_by(consent_token: token)).to be_pending
    end
  end
end
