# frozen_string_literal: true

require "rails_helper"

# Drives the real browser flow: partner → /oauth/authorize → (login) → consent
# → back to the partner. Session state is set by /oauth/authorize itself.
RSpec.describe "OAuth Consent Flow", type: :request do
  let(:redirect_uri) { "https://partner.example.com/auth/bonid/callback" }
  let!(:partner) do
    create(:partner, name: "Unibank", sector: "banking", slug: "unibank",
                     verified_at: Time.current, redirect_uris: [ redirect_uri ])
  end
  let!(:citizen) { create(:user, :verified, first_name: "Jean", last_name: "Louis") }

  def authorize!(state: "partner-state-123")
    get "/oauth/authorize", params: {
      partner: partner.slug, redirect_uri: redirect_uri,
      scope: "openid profile email", state: state
    }
  end

  context "when the citizen is not signed in to BonID" do
    it "sends them to the OTP login with the partner context" do
      authorize!
      expect(response).to redirect_to(%r{/login\?from_partner=unibank})
    end
  end

  context "when the citizen is signed in and has not approved the partner yet" do
    before { sign_in citizen, scope: :citizen }

    it "shows the consent screen" do
      authorize!
      expect(response).to redirect_to(%r{/oauth/consent})

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Unibank")
    end

    it "returns the consent payload as JSON" do
      authorize!
      get "/oauth/consent.json"

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["partner"]["name"]).to eq("Unibank")
      expect(json["requested_scopes"]).to include("openid", "profile")
      expect(json["state"]).to eq("partner-state-123")
    end
  end

  describe "BonID session after handing back to the partner" do
    before do
      allow_any_instance_of(CitizenOtpService).to receive(:generate!).and_return("123456")
      allow_any_instance_of(CitizenOtpService).to receive(:verify!).and_return(true)
    end

    def approve_consent!
      get "/oauth/consent"
      state = response.body[/name="state" value="([^"]+)"/, 1] || "partner-state-123"
      post "/oauth/decision", params: { decision: "approve", state: state }
    end

    it "ends the BonID session when the login started from the partner (like ID.me)" do
      authorize!
      post login_path, params: { citizen: { email: citizen.email }, partner_slug: partner.slug }
      post citizens_verify_otp_path, params: { otp: "123456", partner_slug: partner.slug }
      expect(response).to redirect_to(%r{/oauth/consent})

      approve_consent!
      expect(response).to redirect_to(%r{\A#{Regexp.escape(redirect_uri)}})

      get citizens_dashboard_path
      expect(response).to redirect_to(%r{/login|/citizens/sign_in})
    end

    it "keeps the BonID session when the citizen was already signed in" do
      sign_in citizen, scope: :citizen
      authorize!
      approve_consent!
      expect(response).to redirect_to(%r{\A#{Regexp.escape(redirect_uri)}})

      get citizens_dashboard_path
      expect(response).not_to redirect_to(%r{/login|/citizens/sign_in})
    end
  end

  context "when the citizen already approved the partner" do
    before do
      sign_in citizen, scope: :citizen
      create(:consent_grant, :approved, citizen: citizen, partner: partner,
                                        requested_scopes: %w[openid profile email],
                                        granted_scopes: %w[openid profile email])
    end

    it "shows the redirecting page that hands off to the partner" do
      authorize!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Returning to Unibank")
      expect(response.headers["Cache-Control"]).to include("no-store")

      refresh = response.body[/<meta http-equiv="refresh" content="(\d+);url=([^"]+)"/, 2]
      expect(CGI.unescapeHTML(refresh.to_s)).to start_with(redirect_uri)
      expect(CGI.unescapeHTML(refresh.to_s)).to include("state=partner-state-123", "status=approved")
    end

    it "does not leave a flash behind for the BonID dashboard" do
      authorize!
      expect(flash[:notice]).to be_blank
    end

    it "prompt=consent forces the consent screen anyway" do
      get "/oauth/authorize", params: {
        partner: partner.slug, redirect_uri: redirect_uri, scope: "openid profile email", prompt: "consent"
      }
      expect(response).to redirect_to(%r{/oauth/consent})
    end
  end
end
