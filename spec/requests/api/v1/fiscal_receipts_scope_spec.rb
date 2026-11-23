# frozen_string_literal: true

require "rails_helper"

# Fiscal receipts expose payer data and can burn a citizen's DGI receipt,
# so both actions need an explicit grant in the partner's allowed_scopes —
# for API-key callers too. A granted partner gets past the gate (404 for an
# unknown receipt); anyone else gets 403 before any lookup happens.
RSpec.describe "Api::V1::FiscalReceipts scope gate", type: :request, real_auth: true do
  let(:headers) { { "X-Partner-Api-Key" => "test_api_key", "Content-Type" => "application/json" } }
  let(:receipt) { "DGI-2026-PAP-0048721" }

  def lookup
    get "/api/v1/fiscal_receipts/lookup", params: { receipt_number: receipt }, headers: headers
  end

  def consume
    patch "/api/v1/fiscal_receipts/consume", params: { receipt_number: receipt, officer_id: "X1" }.to_json, headers: headers
  end

  context "partner with no fiscal grant (sector default)" do
    before { create(:partner, :approved, raw_api_key: "test_api_key", sector: "government", allowed_scopes: []) }

    it "refuses lookup" do
      lookup
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["required_scope"]).to eq("fiscal_receipts:read")
    end

    it "refuses consume" do
      consume
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["required_scope"]).to eq("fiscal_receipts:consume")
    end
  end

  context "partner granted read only" do
    before { create(:partner, :approved, raw_api_key: "test_api_key", allowed_scopes: %w[fiscal_receipts:read]) }

    it "passes the gate for lookup" do
      lookup
      expect(response).to have_http_status(:not_found)
    end

    it "still refuses consume" do
      consume
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "partner granted read and consume" do
    before { create(:partner, :approved, raw_api_key: "test_api_key", allowed_scopes: %w[fiscal_receipts:read fiscal_receipts:consume]) }

    it "passes the gate for consume" do
      consume
      expect(response).to have_http_status(:not_found)
    end
  end
end
