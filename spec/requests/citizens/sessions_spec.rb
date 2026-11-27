# frozen_string_literal: true

require "rails_helper"

# Citizens sign in with an email one-time code (password login was removed).
RSpec.describe "Citizens::Sessions", type: :request do
  let!(:citizen) { create(:user, email: "citizen@example.com") }

  describe "legacy Devise entry points" do
    it "GET /citizens/sign_in redirects to the OTP login" do
      get new_citizen_session_path
      expect(response).to redirect_to(%r{/login})
    end

    it "POST /citizens/sign_in redirects to the OTP login" do
      post citizen_session_path, params: { citizen: { email: citizen.email, password: "x" } }
      expect(response).to redirect_to(%r{/login})
    end
  end

  describe "OTP login flow" do
    before do
      allow_any_instance_of(CitizenOtpService).to receive(:generate!).and_return("123456")
    end

    it "requests a code and lands on the verify page" do
      post login_path, params: { citizen: { email: citizen.email } }
      expect(response).to redirect_to(%r{/citizens/verify_otp})
    end

    it "rejects an unknown email" do
      post login_path, params: { citizen: { email: "nobody@example.com" } }
      expect(response).to redirect_to(%r{/login})
      expect(flash[:alert]).to eq(I18n.t("citizen_portal.auth.flash.no_account", locale: :en))
    end

    it "signs the citizen in with a valid code" do
      allow_any_instance_of(CitizenOtpService).to receive(:verify!).and_return(true)

      post login_path, params: { citizen: { email: citizen.email } }
      post citizens_verify_otp_path, params: { otp: "123456" }

      expect(response).to be_redirect
      expect(controller.current_citizen).to eq(citizen)
    end

    it "greets a direct login in the citizen's saved language, not the login page's" do
      citizen.update_columns(preferred_locale: "fr")
      allow_any_instance_of(CitizenOtpService).to receive(:verify!).and_return(true)

      post login_path, params: { citizen: { email: citizen.email }, lang: "en" }
      post citizens_verify_otp_path, params: { otp: "123456" }

      expect(flash[:notice]).to eq(I18n.t("alerts.sign_in.welcome_back", locale: :fr))
      expect(response.location).to include("lang=fr")
    end

    it "does not greet a login that came from a partner" do
      allow_any_instance_of(CitizenOtpService).to receive(:verify!).and_return(true)

      post login_path, params: { citizen: { email: citizen.email }, partner_slug: "zellus" }
      post citizens_verify_otp_path, params: { otp: "123456" }

      welcomes = %i[en fr ht].map { |l| I18n.t("alerts.sign_in.welcome_back", locale: l) }
      expect(welcomes).not_to include(flash[:notice])
    end

    it "rejects an invalid code" do
      allow_any_instance_of(CitizenOtpService).to receive(:verify!).and_return(false)

      post login_path, params: { citizen: { email: citizen.email } }
      post citizens_verify_otp_path, params: { otp: "000000" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("citizen_portal.auth.flash.invalid_code", locale: :en))
    end
  end

  describe "GET /login when already signed in" do
    before { sign_in citizen, scope: :citizen }

    it "skips the OTP form and goes to the dashboard" do
      get login_path
      expect(response).to redirect_to(citizens_dashboard_path)
    end

    it "skips the OTP form when arriving from a partner (e.g. browser Back)" do
      get login_path, params: { from_partner: "zellus" }
      expect(response).to redirect_to(citizens_dashboard_path)
    end
  end

  describe "sign out" do
    it "ends the citizen session" do
      sign_in citizen, scope: :citizen
      delete destroy_citizen_session_path

      expect(response).to be_redirect
      get login_path
      expect(response).to have_http_status(:ok)
    end
  end
end
