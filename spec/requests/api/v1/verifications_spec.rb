require "rails_helper"

RSpec.describe "Api::V1::Verifications", type: :request, real_auth: true do
  let!(:partner) { create(:partner, verified_at: Time.current, active: true, raw_api_key: "test_api_key") }

  let(:headers) do
    {
      "X-Partner-Api-Key" => "test_api_key",
      "Content-Type" => "application/json"
    }
  end

  let(:json_response) { JSON.parse(response.body) }

  describe "POST /api/v1/verify_identity" do
    context "when BonID is verified" do
      let!(:user) { create(:user, :with_address, :verified) }

      it "returns 200 OK with verified data" do
        post "/api/v1/verify_identity", params: { bonid: user.bonid }.to_json, headers: headers
        expect(response).to have_http_status(:ok)
        expect(json_response["status"]).to eq("verified")
        expect(json_response["citizen"]).to include("first_name", "last_name")
        expect(response.headers["X-RateLimit-Limit"]).to be_present
      end
    end

    context "when BonID exists but is not verified" do
      let!(:user) { create(:user, :with_address) }

      before { create(:identity_submission, :pending, user: user, partner: partner) }

      it "returns 404 not_verified" do
        post "/api/v1/verify_identity", params: { bonid: user.bonid }.to_json, headers: headers
        expect(response).to have_http_status(:not_found)
        expect(json_response["status"]).to eq("not_verified")
      end
    end

    context "when BonID is invalid" do
      it "returns 404 not_verified for invalid BonID" do
        post "/api/v1/verify_identity", params: { bonid: "INVALID-BONID" }.to_json, headers: headers
        expect(response).to have_http_status(:not_found)
        expect(json_response["status"]).to eq("not_verified")
      end
    end

    context "when BonID is missing" do
      it "returns 400" do
        post "/api/v1/verify_identity", params: {}.to_json, headers: headers
        expect(response).to have_http_status(:bad_request)
        expect(json_response["error"]).to eq("Missing BonID")
      end
    end

    context "with invalid API key" do
      let(:headers) { { "X-Partner-Api-Key" => "invalid_key", "Content-Type" => "application/json" } }

      it "returns 401" do
        post "/api/v1/verify_identity", params: { bonid: "MO-1968-M-OUEST-P-1001" }.to_json, headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
