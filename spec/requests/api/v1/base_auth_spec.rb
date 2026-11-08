# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API Authentication", type: :request, real_auth: true do
  # Unique key: the factory default ("valid_api_key_123") is shared by every
  # factory partner, so a leftover record from another spec could match first.
  let(:api_key) { "base-auth-#{SecureRandom.hex(8)}" }
  let!(:partner) { create(:partner, verified_at: Time.current, active: true, raw_api_key: api_key) }

  let!(:citizen) { create(:user, :verified) }

  let!(:token) do
    OauthAccessToken.create!(
      partner: partner,
      citizen: citizen,
      token: "valid_token_abc",
      scopes: %w[verifications:verify_identity],
      expires_at: 1.hour.from_now
    )
  end

  describe "GET /api/v1/bonid_status" do
    let(:endpoint) { "/api/v1/bonid_status?bonid=#{citizen.bonid}" }

    context "with valid API key" do
      it "authenticates and returns 200 OK" do
        get endpoint, headers: { "X-Partner-Api-Key" => api_key }
        expect(response).to have_http_status(:ok)
        expect(response.headers).to include("X-BonID-API-Version")
      end
    end

    context "with valid Bearer token" do
      it "authenticates and returns 200 OK" do
        get endpoint, headers: { "Authorization" => "Bearer valid_token_abc" }
        expect(response).to have_http_status(:ok)
        expect(response.headers["X-BonID-Granted-Scopes"]).to include("verifications")
      end
    end

    context "with expired token" do
      before { token.update!(expires_at: 1.hour.ago) }

      it "returns 401 unauthorized" do
        get endpoint, headers: { "Authorization" => "Bearer valid_token_abc" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with missing credentials" do
      it "returns 401 unauthorized" do
        get endpoint
        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body["error"]).to eq("Missing credentials")
      end
    end
  end
end
