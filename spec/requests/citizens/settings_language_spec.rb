# frozen_string_literal: true

require "rails_helper"

# Paramèt → Lang: the citizen's saved language drives the whole portal.
RSpec.describe "Citizen settings — language", type: :request do
  let!(:citizen) { create(:user, is_diaspora: false) }

  before { sign_in citizen, scope: :citizen }

  it "renders the portal in Kreyòl by default" do
    get citizens_settings_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sekirite", "Preferans", "Jere aparèy", "Dekonekte")
    expect(response.body).to include('<html lang="ht"')
  end

  it "ignores a ?lang= param that disagrees with the saved preference" do
    get citizens_settings_path(lang: "en")
    expect(response.body).to include("Sekirite")
    expect(response.body).not_to include("Manage devices")
  end

  %w[fr en].each do |locale|
    it "switches to #{locale} when picked and keeps it across pages" do
      patch citizens_settings_path, params: { user: { preferred_locale: locale } }

      expect(citizen.reload.preferred_locale).to eq(locale)
      expect(response).to redirect_to(citizens_settings_path(lang: locale))
      expect(flash[:notice]).to eq(I18n.t("citizen_portal.settings.flash.saved", locale: locale))

      get citizens_dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("citizen_portal.nav.sign_out", locale: locale))
      expect(response.body).to include(I18n.t("citizen_portal.dashboard.get_started.title", locale: locale))
    end
  end

  %w[fr en].each do |locale|
    it "renders Activity in #{locale}" do
      citizen.update!(preferred_locale: locale)
      get citizens_activity_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("citizen_portal.activity.title", locale: locale))
      expect(response.body).to include(I18n.t("citizen_portal.activity.export_pdf", locale: locale))
    end

    it "renders onboarding in #{locale}" do
      citizen.update_columns(preferred_locale: locale, is_diaspora: nil)
      get citizens_onboarding_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("citizen_portal.onboarding.question", locale: locale))
    end
  end

  %w[ht fr en].each do |locale|
    it "renders the profile wizard in #{locale}" do
      citizen.update!(preferred_locale: locale)
      get edit_citizens_profile_path
      expect(response).to have_http_status(:ok)
      %w[title personal.title id.title address.title review.title].each do |key|
        expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.profile.#{key}", locale: locale)))
      end
      expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.confirm.confirm", locale: locale)))
    end

    it "renders the dashboard edit pop-ups in #{locale}" do
      allow(WalletProfileCardsPausable).to receive(:enabled_cards).and_return(WalletProfileCardsPausable::CARDS)
      citizen.update!(preferred_locale: locale)
      get citizens_dashboard_path
      %w[health.blood_type physical.eye_color social.add_platform bank.account_type].each do |key|
        expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.profile.#{key}", locale: locale)))
      end
    end
  end

  describe "wallet profile cards switch" do
    it "hides the profile cards and their pop-ups by default (v1)" do
      get citizens_dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('id="healthModal"')
      expect(response.body).not_to include('data-card="health"')
    end

    it "shows them when enabled in WALLET_PROFILE_CARDS" do
      allow(WalletProfileCardsPausable).to receive(:enabled_cards).and_return(WalletProfileCardsPausable::CARDS)
      get citizens_dashboard_path
      expect(response.body).to include('id="healthModal"')
    end

    it "shows only the cards that are enabled" do
      allow(WalletProfileCardsPausable).to receive(:enabled_cards).and_return(%w[emergency])
      get citizens_dashboard_path
      expect(response.body).to include('id="emergencyModal"')
      expect(response.body).not_to include('id="healthModal"')
    end
  end

  describe "Get your BonID" do
    let!(:citizen) { create(:user, :profile_complete, :with_address, is_diaspora: false) }

    %w[ht fr en].each do |locale|
      it "renders the submission wizard in #{locale}" do
        citizen.update!(preferred_locale: locale)
        get new_citizens_identity_submission_path
        expect(response).to have_http_status(:ok)
        %w[title gov_id_title supporting_title face_title signature_title review.confirm_html
           scan_tips.title proof.picker_label signature.draw].each do |key|
          text = I18n.t("citizen_portal.submission.#{key}", locale: locale)
          text = text.split("<strong>").first.strip if key.end_with?("_html")
          expect(response.body).to include(CGI.escapeHTML(text).presence || text)
        end
      end

      it "renders scan history in #{locale}" do
        citizen.update!(preferred_locale: locale)
        get scan_history_citizens_identity_submissions_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.submission.scan_history.title", locale: locale)))
      end
    end
  end

  describe "Konsantman, election and name change" do
    let!(:citizen) { create(:user, :with_address, :identity_verified) }

    %w[ht fr en].each do |locale|
      it "renders the election page in #{locale}" do
        citizen.update!(preferred_locale: locale)
        get citizens_election_enrollment_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.election.enrollment.title", locale: locale)))
      end

      it "renders the name change form in #{locale}" do
        citizen.update!(preferred_locale: locale)
        get new_citizens_name_change_request_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(CGI.escapeHTML(I18n.t("citizen_portal.name_change.title", locale: locale)))
      end

      it "renders an active access card in #{locale}" do
        citizen.update!(preferred_locale: locale)
        partner = create(:partner, :approved, name: "Zèllus")
        ConsentGrant.create!(citizen: citizen, partner: partner, status: :approved,
                             requested_scopes: %w[openid profile], granted_scopes: %w[openid profile],
                             granted_at: 1.day.ago, expires_at: 30.days.from_now)
        get citizens_consents_path
        body = response.body
        expect(body).to include(CGI.escapeHTML(I18n.t("citizen_portal.consents.statuses.approved", locale: locale)))
        expect(body).to include(CGI.escapeHTML(I18n.t("citizen_portal.consents.scope_labels.profile", locale: locale)))
      end
    end
  end

  it "rejects an unsupported language" do
    patch citizens_settings_path, params: { user: { preferred_locale: "es" } }
    expect(citizen.reload.preferred_locale).to eq("ht")
  end
end
