# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth Consent Flow", type: :request do
  let!(:partner)  { Partner.create!(name: "Unibank", sector: "banking", slug: "unibank", verified_at: Time.current) }
  let!(:citizen)  { create(:user, :verified, email: "jean@example.ht", first_name: "Jean", last_name: "Louis") }

  before do
    sign_in citizen, scope: :citizen
  end

  describe "GET /oauth/consent.json" do
    it "returns valid JSON consent payload" do
      get "/oauth/consent.json", params: { partner: "unibank", scopes: "profile,email" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["partner"]["name"]).to eq("Unibank")
      expect(json["requested_scopes"]).to include("profile", "email")
      expect(json["citizen"]["bonid"]).to be_present
      expect(json["consent"]["approve_url"]).to match(/decision\.json/)
    end
  end

  describe "GET /oauth/consent (HTML)" do
    it "renders the consent page for a verified citizen" do
      # simulate web flow
      session[:pending_consent] = { partner_id: partner.id, scopes: %w[profile email] }
      get "/oauth/consent"
      expect(response).to render_template(:consent)
      expect(response.body).to include("Authorize Data Access")
    end
  end
end
