require "rails_helper"

# The email-change flow re-renders the Settings page (code entry, wrong
# code, …), which lists known devices — those must be loaded on #update too.
RSpec.describe "Citizen settings — email change", type: :request do
  let!(:citizen) { create(:user, :with_address, :identity_verified) }

  before { sign_in citizen, scope: :citizen }

  it "requesting a code renders the code-entry step" do
    patch citizens_settings_path, params: { user: { email: "nouveau@example.com" } }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("nouveau@example.com")
    expect(response.body).to include('data-otp-input-target="box"')
  end

  it "a wrong code re-renders the page instead of erroring" do
    patch citizens_settings_path, params: { user: { email: "nouveau@example.com" } }
    patch citizens_settings_path, params: { user: { email: "nouveau@example.com", email_change_code: "000000" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(citizen.reload.email).not_to eq("nouveau@example.com")
  end

  it "entering the current email reopens the modal with a clear message" do
    patch citizens_settings_path, params: { user: { email: citizen.email.upcase } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.settings.flash.same_email")))
    expect(response.body).to include('data-auto-modal-target-id-value="emailChangeModal"')
    expect(response.body).not_to include(I18n.t("citizen_portal.settings.flash.no_changes"))
  end

  it "an email used by another account reopens the modal with the error and keeps the typed address" do
    other = create(:user, :with_address, :identity_verified)
    patch citizens_settings_path, params: { user: { email: other.email } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.settings.flash.email_in_use")))
    expect(response.body).to include('data-auto-modal-target-id-value="emailChangeModal"')
    expect(response.body).to include(%(value="#{other.email}"))
  end
end
