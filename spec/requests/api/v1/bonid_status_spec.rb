# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::BonidStatus", type: :request do
  let!(:partner) do
    Partner.create!(
      name: "BonID Partner",
      verified_at: Time.current,
      active: true,
      api_key_digest: BCrypt::Password.create("test_api_key")
    )
  end

  let(:headers) { { "X-Partner-Api-Key" => "test_api_key", "Content-Type" => "application/json" } }

  before do
    allow_any_instance_of(Api::V1::BonidStatusController)
      .to receive(:authenticate_api_key!)
      .and_return(true)
    allow_any_instance_of(Api::V1::BonidStatusController)
      .to receive(:instance_variable_get)
      .with(:@current_partner)
      .and_return(partner)
  end

  describe "GET /api/v1/bonid_status" do
    context "when BonID exists and is approved" do
      let!(:user) { create(:user, :with_address, bonid: "HT2025-123") }
      let!(:submission) { create(:identity_submission, user: user, status: :approved, verified_at: Time.current) }

      it "returns active status" do
        get "/api/v1/bonid_status", params: { bonid: user.bonid }, headers: headers
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["bonid"]).to eq(user.bonid)
        expect(json["status"]).to eq("approved")
      end
    end

    context "when BonID does not exist" do
      it "returns not_found" do
        get "/api/v1/bonid_status", params: { bonid: "INVALID-BONID" }, headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when BonID param missing" do
      it "returns bad_request" do
        get "/api/v1/bonid_status", headers: headers
        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
