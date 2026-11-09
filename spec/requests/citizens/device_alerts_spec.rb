# frozen_string_literal: true

require "rails_helper"

# New-device sign-in alerts + "sign out everywhere".
RSpec.describe "Citizen device alerts & session revocation", type: :request do
  include ActiveJob::TestHelper

  let!(:citizen) { create(:user, email: "citizen@example.com", is_diaspora: false) }

  before do
    allow_any_instance_of(CitizenOtpService).to receive(:generate!).and_return("123456")
    allow_any_instance_of(CitizenOtpService).to receive(:verify!).and_return(true)
  end

  def log_in(browser)
    browser.post login_path, params: { citizen: { email: citizen.email } }
    browser.post citizens_verify_otp_path, params: { otp: "123456" }
  end

  def signed_in?(browser)
    browser.get citizens_settings_path
    browser.response.status == 200
  end

  def alert_mails
    ActionMailer::Base.deliveries.select { |m| m.subject == "BonID: Nouvo koneksyon sou kont ou" }
  end

  let(:laptop) { open_session }
  let(:phone)  { open_session }

  around { |ex| perform_enqueued_jobs { ex.run } }
  before { ActionMailer::Base.deliveries.clear }

  it "registers the first device silently" do
    log_in(laptop)
    expect(citizen.known_devices.count).to eq(1)
    expect(alert_mails).to be_empty
  end

  it "does not alert when the same browser signs in again" do
    log_in(laptop)
    laptop.delete destroy_citizen_session_path
    log_in(laptop)
    expect(citizen.known_devices.count).to eq(1)
    expect(alert_mails).to be_empty
  end

  it "alerts when a second browser signs in, and both stay signed in" do
    log_in(laptop)
    log_in(phone)

    expect(citizen.known_devices.count).to eq(2)
    expect(alert_mails.size).to eq(1)
    expect(alert_mails.first.to).to eq([ citizen.email ])
    expect(alert_mails.first.text_part.body.to_s).to include("/citizens/sesyon/revoke?token=")
    expect(signed_in?(laptop)).to be(true)
    expect(signed_in?(phone)).to be(true)
  end

  it "settings → sign out other devices keeps this one, drops the rest" do
    log_in(laptop)
    log_in(phone)

    laptop.delete citizens_sign_out_other_devices_path
    expect(URI(laptop.response.location).path).to eq(citizens_settings_path)

    expect(signed_in?(laptop)).to be(true)
    expect(signed_in?(phone)).to be(false)
  end

  it "settings lists each device and marks the current one" do
    log_in(laptop)
    log_in(phone)

    phone.get citizens_settings_path
    body = phone.response.body
    expect(body.scan(%r{<li class="d-flex align-items-start gap-2 py-2"}).size).to eq(2)
    expect(body.scan("APARÈY SA A").size).to eq(1)
    expect(body).to include("Dènye fwa: gen")
  end

  describe "'This wasn't me' link" do
    let(:token) do
      log_in(laptop)
      log_in(phone)
      URI.decode_www_form_component(alert_mails.first.text_part.body.to_s[/token=([^\s]+)/, 1])
    end

    it "GET only shows a confirm page (safe against link prefetch)" do
      get citizens_session_revocation_path(token: token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign out of every device?")
      expect(signed_in?(phone)).to be(true)
    end

    it "POST signs out every device, forgets the flagged one, and is single-use" do
      token # log both browsers in first
      flagged = citizen.known_devices.order(:created_at).last

      post citizens_session_revocation_path, params: { token: token }
      expect(response.body).to include("You're signed out everywhere")

      expect(signed_in?(laptop)).to be(false)
      expect(signed_in?(phone)).to be(false)
      expect(KnownDevice.exists?(flagged.id)).to be(false)

      post citizens_session_revocation_path, params: { token: token }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("This link has expired")
    end

    it "rejects a forged token" do
      post citizens_session_revocation_path, params: { token: "nope" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
