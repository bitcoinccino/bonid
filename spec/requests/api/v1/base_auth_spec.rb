# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API Authentication", type: :request do
  let!(:partner) do
    Partner.create!(
      name: "Test Partner",
      slug: "test-partner",
      verified_at: Time.current,
      active: true,
      api_key_digest: BCrypt::Password.create("valid_api_key_123")
    )
  end

  let!(:citizen) { User.create!(email: "citizen@test.com", password: "password123") }

  let!(:token) do
    OAuthAccessToken.create!(
      partner: partner,
      citizen: citizen,
      token: "valid_token_abc",
      scopes: %w[verifications:verify_identity],
      expires_at: 1.hour.from_now
    )
  end

  describe "GET /api/v1/bonid_status" do
    let(:endpoint) { "/api/v1/bonid_status?bonid=MO-1968-M-OUEST-P-6790" }

    context "with valid API key" do
      it "authenticates and returns 200 OK" do
        get endpoint, headers: { "X-Partner-Api-Key" => "valid_api_key_123" }
        expect(response).to have_http_status(:ok)
        expect(response.headers).to include("X-BonID-API-Version")
      end
    end

    context "with valid Bearer token" do
      it "authenticates and returns 200 OK" do
        get endpoint, headers: { "Authorization" => "Bearer valid_token_abc" }
        expect(response).to have_http_status(:ok)
        expect(response.headers["X-BonID-Scopes"]).to include("verifications")
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
