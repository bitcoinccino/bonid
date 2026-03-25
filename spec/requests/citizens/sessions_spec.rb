# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Citizens::Sessions", type: :request do
  include Devise::Test::IntegrationHelpers

  before(:all) do
    # ✅ Ensure Devise knows this scope is :citizen (BonID citizen)
    Devise.mappings[:user] = Devise.mappings[:citizen]
  end

  let!(:citizen) do
    create(:user,
      email: "citizen@example.com",
      password: "password123",
      role: :citizen)
  end

  describe "GET /citizens/sign_in" do
    it "redirects to OTP login" do
      get new_citizen_session_path
      expect(response).to redirect_to(citizens_otp_sign_in_path)
    end
  end

  describe "POST /citizens/sign_in and sign_out" do
    it "redirects POST to OTP login" do
      post citizen_session_path, params: {
        citizen: { email: citizen.email, password: "password123" }
      }

      expect(response).to redirect_to(citizens_otp_sign_in_path)
    end

    it "signs out cleanly" do
      sign_in citizen, scope: :citizen
      delete destroy_citizen_session_path
      expect(response).to redirect_to(citizens_otp_sign_in_path)
    end
  end

  describe "OTP Login Flow" do
    before do
      allow_any_instance_of(CitizenOtpService).to receive(:generate_otp).and_return("123456")
      allow_any_instance_of(CitizenOtpService).to receive(:valid_otp?).and_return(true)
    end

    it "generates and verifies OTP successfully" do
      post citizens_create_otp_path, params: { citizen: { email: citizen.email } }
      expect(response).to redirect_to(citizens_verify_otp_path)

      # Simulate OTP entry
      post citizens_verify_otp_path, params: { otp: "123456" }
      expect(response).to redirect_to(citizens_identity_submissions_path)
    end

    it "rejects invalid OTP" do
      allow_any_instance_of(CitizenOtpService).to receive(:valid_otp?).and_return(false)
      post citizens_create_otp_path, params: { citizen: { email: citizen.email } }
      post citizens_verify_otp_path, params: { otp: "000000" }
      expect(response.body).to include("Invalid or expired code")
    end

    it "resends OTP successfully" do
      session = { pending_citizen_id: citizen.id }
      post citizens_resend_otp_path, params: {}, session: session
      expect(response.body).to include("We sent you a new code").or include("OTP resent")
    end
  end
end
