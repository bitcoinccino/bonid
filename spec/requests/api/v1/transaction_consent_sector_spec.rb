# frozen_string_literal: true

require "rails_helper"

# A partner's sector decides which transaction types it may use and which
# details (scopes) it may ask a citizen for.
RSpec.describe "Transaction consents limited by partner sector", type: :request, real_auth: true do
  let!(:citizen) do
    create(:user, :with_address, :identity_verified,
           first_name: "Davidson", last_name: "Louis", bonid: "DL-1990-M-OU-P0000-TST")
  end

  # One real sector from each group
  SECTOR_FOR_GROUP = {
    "finance" => "banking", "government" => "ministry", "law_enforcement" => "law_enforcement",
    "diplomacy" => "embassy", "healthcare" => "hospital", "civil" => "notary", "default" => "retail"
  }.freeze

  def partner_in(sector, key)
    create(:partner, :approved, sector: sector, raw_api_key: key)
  end

  def request_consent(key, type:, scopes:)
    post "/api/v1/transaction_consents",
         params: { bonid: citizen.bonid, transaction_type: type, scopes: scopes }.to_json,
         headers: { "X-Partner-Api-Key" => key, "Content-Type" => "application/json" }
    JSON.parse(response.body)
  end

  SECTOR_FOR_GROUP.each do |group, sector|
    context "#{group} partner (#{sector})" do
      let(:key) { "key_#{group}" }
      let!(:partner) { partner_in(sector, key) }
      let(:allowed_scopes) { TransactionConsent::DEFAULT_SCOPES_BY_SECTOR.fetch(group) }
      let(:allowed_types)  { TransactionConsent::DEFAULT_TRANSACTION_TYPES_BY_SECTOR.fetch(group) }

      it "gets its sector's types by default" do
        expect(partner.reload.effective_allowed_transaction_types).to match_array(allowed_types)
      end

      it "can ask for every scope its sector allows" do
        request_consent(key, type: allowed_types.first, scopes: allowed_scopes)
        expect(response).to have_http_status(:created), response.body
      end

      it "is refused scopes outside its sector, and told what it can ask for" do
        outside = (TransactionConsent::CONSENT_SCOPES - allowed_scopes).first
        body = request_consent(key, type: allowed_types.first, scopes: ["profile", outside])
        expect(response).to have_http_status(:forbidden)
        expect(body["error"]).to include(outside)
        expect(body["allowed_scopes"]).to match_array(allowed_scopes)
      end

      it "is refused transaction types outside its sector" do
        outside = (TransactionConsent::VALID_TRANSACTION_TYPES - allowed_types).first
        request_consent(key, type: outside, scopes: ["profile"])
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  it "never lets a bank ask for health records" do
    partner_in("banking", "bank_key")
    request_consent("bank_key", type: "kyc_check", scopes: %w[profile health])
    expect(response).to have_http_status(:forbidden)
  end

  it "lets an embassy ask for social media handles on a visa check" do
    partner_in("embassy", "embassy_key")
    request_consent("embassy_key", type: "visa_processing", scopes: %w[profile social])
    expect(response).to have_http_status(:created), response.body
  end

  it "doesn't let a bank ask for social media handles" do
    partner_in("banking", "bank_key")
    request_consent("bank_key", type: "kyc_check", scopes: %w[profile social])
    expect(response).to have_http_status(:forbidden)
  end

  it "lets a hospital ask for health records on a medical consultation" do
    partner_in("hospital", "hospital_key")
    request_consent("hospital_key", type: "medical_consultation", scopes: %w[profile health])
    expect(response).to have_http_status(:created), response.body
  end

  it "rejects made-up scope names instead of silently returning nothing" do
    partner_in("banking", "bank_key")
    body = request_consent("bank_key", type: "kyc_check", scopes: %w[identity])
    expect(response).to have_http_status(:unprocessable_entity)
    expect(body["valid_scopes"]).to include("profile")
  end

  it "gives no sector the all-access identity:details scope by default" do
    expect(TransactionConsent::DEFAULT_SCOPES_BY_SECTOR.values.flatten).not_to include("identity:details")
  end

  it "only uses scopes the identity filter understands" do
    expect(TransactionConsent::DEFAULT_SCOPES_BY_SECTOR.values.flatten.uniq - TransactionConsent::CONSENT_SCOPES).to be_empty
  end
end
