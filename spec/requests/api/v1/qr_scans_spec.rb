# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::QrScans", type: :request do
  let!(:partner) do
    Partner.create!(
      name: "QR Partner",
      verified_at: Time.current,
      active: true,
      api_key_digest: BCrypt::Password.create("secret_key")
    )
  end

  let(:headers) { { "X-Partner-Api-Key" => "secret_key", "Content-Type" => "application/json" } }

  before do
    allow_any_instance_of(Api::V1::QrScansController)
      .to receive(:authenticate_api_key!)
      .and_return(true)
    allow_any_instance_of(Api::V1::QrScansController)
      .to receive(:instance_variable_get)
      .with(:@current_partner)
      .and_return(partner)
  end

  describe "POST /api/v1/qr_scan" do
    let!(:user) { create(:user, :with_address, bonid: "HT-QR-9999") }

    context "with valid QR data" do
      # simulate Base64 encoded QR JSON
      let(:qr_data) { Base64.encode64({ bonid: user.bonid }.to_json) }

      it "returns verified if user exists" do
        post "/api/v1/qr_scan", params: { qr_data: qr_data }, headers: headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["status"]).to eq("verified")
      end
    end

    context "with invalid QR data" do
      it "returns 404 invalid" do
        post "/api/v1/qr_scan", params: { qr_data: Base64.encode64({ bonid: "NOPE" }.to_json) }, headers: headers
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
