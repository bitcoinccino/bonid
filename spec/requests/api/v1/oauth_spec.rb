# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::OAuth Flow", type: :request do
  let!(:partner)  { Partner.find_by("verified_at IS NOT NULL AND active = ?", true) || create(:partner, verified_at: Time.current, active: true) }
  let!(:citizen)  { User.joins(:roles).find_by(roles: { name: "citizen" }) || create(:user) }

  describe "POST /api/v1/oauth/token" do
    it "issues a new access token for a verified partner and citizen" do
      post "/api/v1/oauth/token", params: {
        partner_id: partner.id,
        citizen_id: citizen.id
      }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["access_token"]).to be_present
      expect(data["expires_in"]).to be_present
      expect(data["refresh_token"]).to be_present
    end

    it "rejects request when partner is invalid" do
      post "/api/v1/oauth/token", params: {
        partner_id: 999_999,
        citizen_id: citizen.id
      }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects when required parameters are missing" do
      post "/api/v1/oauth/token", params: { citizen_id: citizen.id }
      expect(response).to have_http_status(:bad_request).or have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /api/v1/oauth/revoke" do
    let!(:token) do
      OAuthAccessToken.create!(
        partner: partner,
        citizen: citizen,
        expires_at: 1.hour.from_now
      )
    end

    it "revokes a valid access token" do
      post "/api/v1/oauth/revoke", headers: { "Authorization" => "Bearer #{token.token}" }

      expect(response).to have_http_status(:ok)
      expect(token.reload.revoked?).to be true
    end

    it "returns unauthorized for an invalid token" do
      post "/api/v1/oauth/revoke", headers: { "Authorization" => "Bearer invalidtoken" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/oauth/refresh" do
    let!(:token) do
      OAuthAccessToken.create!(
        partner: partner,
        citizen: citizen,
        expires_at: 1.hour.from_now
      )
    end

    it "refreshes a valid token" do
      post "/api/v1/oauth/refresh", params: { refresh_token: token.refresh_token }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["access_token"]).to be_present
      expect(data["refresh_token"]).to be_present
      expect(data["access_token"]).not_to eq(token.token)
    end

    it "rejects invalid refresh tokens" do
      post "/api/v1/oauth/refresh", params: { refresh_token: "badtoken" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects when token is expired" do
      expired = OAuthAccessToken.create!(
        partner: partner,
        citizen: citizen,
        expires_at: 1.hour.ago
      )

      post "/api/v1/oauth/refresh", params: { refresh_token: expired.refresh_token }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
