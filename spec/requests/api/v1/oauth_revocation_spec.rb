# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth Revocation & Refresh", type: :request do
  let!(:partner) { Partner.create!(name: "Partner", slug: "partner", verified_at: Time.current, active: true) }
  let!(:citizen) { User.create!(email: "citizen@example.com", password: "password123") }
  let!(:token) do
    OAuthAccessToken.create!(
      partner: partner,
      citizen: citizen,
      token: SecureRandom.hex(32),
      refresh_token: SecureRandom.hex(32),
      scopes: %w[verifications:verify_identity],
      expires_at: 1.hour.from_now
    )
  end

  describe "POST /api/v1/oauth/revoke" do
    it "revokes a valid token" do
      post "/api/v1/oauth/revoke", headers: { "Authorization" => "Bearer #{token.token}" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("revoked")
      expect(token.reload.revoked_at).to be_present
    end

    it "returns 404 for invalid token" do
      post "/api/v1/oauth/revoke", params: { token: "invalid_token" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/oauth/token (refresh)" do
    it "issues a new token using refresh_token" do
      post "/api/v1/oauth/token", params: { grant_type: "refresh_token", refresh_token: token.refresh_token }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["access_token"]).not_to eq(token.token)
      expect(token.reload.token).not_to eq(token.refresh_token)
    end

    it "rejects invalid refresh_token" do
      post "/api/v1/oauth/token", params: { grant_type: "refresh_token", refresh_token: "bad" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
