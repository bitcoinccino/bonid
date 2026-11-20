# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Citizen OTP resend", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  before { post "/login", params: { citizen: { email: user.email } } }

  it "shows a single resend control on the verify page" do
    follow_redirect!
    expect(response.body.scan('id="resend-button"').size).to eq(1)
    expect(response.body).not_to include("resend it")
  end

  it "redirects back to the verify page with a fresh code that logs in" do
    travel 31.seconds do
      sent = nil
      allow_any_instance_of(CitizenOtpService).to receive(:generate!).and_wrap_original do |m, *a, **k|
        sent = m.call(*a, **k)
      end

      post "/citizens/resend_otp", params: { email: user.email, signup: "false" }

      expect(response).to redirect_to(%r{/citizens/verify_otp})
      expect(flash[:notice]).to eq(I18n.t("citizen_portal.auth.flash.new_code_sent"))
      expect(sent).to match(/\A\d{6}\z/)

      post "/citizens/verify_otp", params: { otp: sent, email: user.email }
      expect(response).to have_http_status(:redirect)
      expect(response.location).not_to include("verify_otp")
    end
  end

  it "asks the citizen to wait when resending within the cooldown" do
    post "/citizens/resend_otp", params: { email: user.email }

    expect(response).to redirect_to(%r{/citizens/verify_otp})
    expect(flash[:alert]).to eq(I18n.t("citizen_portal.auth.flash.resend_wait"))
  end

  it "sends the citizen back to login when the pending session is gone" do
    reset!
    post "/citizens/resend_otp", params: { email: user.email }
    expect(response).to redirect_to(%r{/login})
  end
end
