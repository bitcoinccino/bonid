# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Consent Grants API", type: :request do
  let!(:partner) { create(:partner) }
  let!(:user)    { create(:user, bonid: "MO-1968-M-OUEST-P-6790") }

  # ✅ Disable partner authentication for all API v1 controllers
  before do
    allow_any_instance_of(Api::V1::BaseController)
      .to receive(:authenticate_partner!)
      .and_return(true)
  end

  describe "POST /api/v1/request_consent" do
    it "creates a new pending consent grant for a citizen" do
      headers = {
        "X-Partner-Api-Key" => partner.raw_api_key,
        "CONTENT_TYPE" => "application/json"
      }

      post "/api/v1/request_consent",
           params: { bonid: user.bonid, scopes: %w[identity bank] },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body).to include("grant_token")

      grant = ConsentGrant.find_by(grant_token: body["grant_token"])
      expect(grant).to be_present
      expect(grant.status).to eq("pending")
      expect(grant.requested_scopes).to include("identity", "bank")
    end
  end

  describe "GET /api/v1/citizen/approve_consent" do
    let!(:grant) do
      create(:consent_grant,
             citizen: user,
             partner: partner,
             grant_token: "test123",
             requested_scopes: %w[identity bank],
             status: :pending)
    end

    it "approves the consent grant" do
      get "/api/v1/citizen/approve_consent",
          params: { grant_token: "test123", decision: "approve" },
          as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["message"]).to eq("Consent approved successfully")
      expect(body["status"]).to eq("approved")
      expect(body["approved_scopes"]).to match_array(%w[identity bank])

      grant.reload
      expect(grant).to be_approved
    end

    it "revokes the consent grant when denied" do
      get "/api/v1/citizen/approve_consent",
          params: { grant_token: "test123", decision: "deny" },
          as: :json

      expect(response).to have_http_status(:ok)
      grant.reload
      expect(grant).to be_revoked
    end

    it "returns an error for invalid token" do
      get "/api/v1/citizen/approve_consent",
          params: { grant_token: "fake_token", decision: "approve" },
          as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Invalid or expired token")
    end
  end
end
