# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::QrScans", type: :request, real_auth: true do
  let!(:partner) { create(:partner, verified_at: Time.current, active: true, raw_api_key: "secret_key") }

  let(:headers) { { "X-Partner-Api-Key" => "secret_key", "Content-Type" => "application/json" } }


  describe "POST /api/v1/qr_scan" do
    let!(:user) { create(:user, :with_address, :verified) }

    context "with valid QR data" do
      # simulate Base64 encoded QR JSON
      let(:qr_data) { Base64.encode64({ bonid: user.bonid }.to_json) }

      it "returns verified if user exists" do
        post "/api/v1/qr_scan", params: { qr_data: qr_data }.to_json, headers: headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["status"]).to eq("verified")
      end
    end

    context "with invalid QR data" do
      it "returns 404 invalid" do
        post "/api/v1/qr_scan", params: { qr_data: Base64.encode64({ bonid: "NOPE" }.to_json) }.to_json, headers: headers
        expect(response).to have_http_status(:not_found)
        expect(JSON.parse(response.body)["status"]).to eq("invalid")
      end
    end

    context "when qr_data missing" do
      it "returns bad_request" do
        post "/api/v1/qr_scan", headers: headers
        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
