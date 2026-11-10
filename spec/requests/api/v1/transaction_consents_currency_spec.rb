# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/transaction_consents currency validation", type: :request, real_auth: true do
  let!(:partner) { create(:partner, :approved, raw_api_key: "test_api_key") }
  let(:headers)  { { "X-Partner-Api-Key" => "test_api_key", "Content-Type" => "application/json" } }
  let!(:citizen) { create(:user, :with_address, bonid: "BZ-1970-M-ND-P2334-0B6") }

  def create_consent(**body)
    post "/api/v1/transaction_consents",
         params: { bonid: citizen.bonid, transaction_type: "wire_transfer", scopes: %w[profile] }.merge(body).to_json,
         headers: headers
  end

  it "accepts a supported currency" do
    expect { create_consent(amount: 5000, currency: "HTG") }.to change(TransactionConsent, :count).by(1)
    expect(response).to have_http_status(:created)
  end

  it "rejects an unsupported currency with 422 and a clear message" do
    expect { create_consent(amount: 100, currency: "XYZ") }.not_to change(TransactionConsent, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to include("not supported")
  end

  it "rejects crypto on a non-crypto transaction" do
    create_consent(amount: "0.002", currency: "BTC")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to include("only allowed on crypto")
  end
end
