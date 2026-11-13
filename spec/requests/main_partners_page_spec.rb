# frozen_string_literal: true

require "rails_helper"

# Public partner directory (/partners): real verified partners only, one
# plain line per partner, and a "Sign in with BonID" badge only when the
# partner has a live OAuth integration on its own site.
RSpec.describe "Public partner directory", type: :request do
  let!(:bank)    { create(:partner, name: "Banque Test", sector: "banking", verified_at: 1.day.ago) }
  let!(:central) { create(:partner, name: "BonID Central", slug: "bonid-central", verified_at: 1.day.ago) }
  let!(:pending) { create(:partner, name: "Pas Encore", verified_at: nil) }

  it "lists verified partners but hides the internal fallback partner" do
    get partners_path(lang: "fr")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Banque Test")
    expect(response.body).not_to include("BonID Central", "Pas Encore")
  end

  it "shows the everyday problem and how BonID solves it, not the old bullet list" do
    get partners_path(lang: "fr")

    expect(response.body).to include(CGI.escapeHTML(I18n.t("main.partners.uses.banking.problem", locale: :fr)))
    expect(response.body).to include(CGI.escapeHTML(I18n.t("main.partners.uses.banking.solution", locale: :fr)))
    expect(response.body).not_to include("Ouvrez un compte bancaire instantanément")
  end

  describe "Sign in with BonID button" do
    let(:label) { CGI.escapeHTML(I18n.t("main.partners.sign_in_badge", locale: :ht)) }

    def link_oauth(partner, redirect_uri)
      partner.oauth_application&.destroy
      create(:oauth_application, partner: partner, name: partner.name, uid: SecureRandom.hex(8), redirect_uri: redirect_uri)
    end

    it "links to the partner's site when it has a live BonID sign-in" do
      linked = create(:partner, name: "Appli Liée", sector: "fintech", website: "appli.example.com", verified_at: 1.day.ago)
      link_oauth(linked, "https://appli.example.com/callback")

      get partners_path(lang: "ht")

      expect(response.body.scan(label).size).to eq(1)
      expect(response.body).to include('href="https://appli.example.com"')
      expect(response.body).to include(CGI.escapeHTML(I18n.t("main.partners.get_verified", locale: :ht)))
    end

    it "is hidden without a real redirect URI or without a website" do
      link_oauth(bank, "urn:ietf:wg:oauth:2.0:oob")
      no_site = create(:partner, name: "Sans Site", website: nil, verified_at: 1.day.ago)
      link_oauth(no_site, "https://sans-site.example.com/callback")

      get partners_path(lang: "ht")

      expect(response.body).not_to include(label)
    end
  end

  it "treats search text literally" do
    get partners_path(lang: "fr", search: "%")

    expect(response.body).not_to include("Banque Test")
  end

  describe "sector sections and chips" do
    let!(:cep) { create(:partner, name: "CEP Test", sector: "cep", verified_at: 1.day.ago) }

    it "shows a short list as one grid, without section headings" do
      get partners_path(lang: "fr")

      expect(response.body).to include("CEP Test", "Banque Test")
      expect(response.body).not_to include('class="partners-section__title"')
    end

    it "groups partners under a heading per sector group once the list is long, legacy sectors included" do
      stub_const("MainController::GROUPED_DIRECTORY_MIN", 1)
      get partners_path(lang: "fr")

      expect(response.body.scan('class="partners-section__title"').size).to eq(2)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("main.partners.sector_groups.finance", locale: :fr)))
      expect(response.body).to include(CGI.escapeHTML(I18n.t("main.partners.sector_groups.government", locale: :fr)))
    end

    it "shows a chip per group and narrows to one group when tapped" do
      get partners_path(lang: "fr", group: "government")

      expect(response.body).to include("CEP Test")
      expect(response.body).not_to include("Banque Test")
      # chips keep every group, with the picked one marked active
      expect(response.body).to include("/partners?group=finance")
      expect(response.body).to match(/class="partners-chip is-active"[^>]*href="\/partners\?group=government/)
    end

    it "shows the 6 biggest groups and puts the rest behind a + N chip" do
      %w[embassy hospital university mobile_carrier hotel law_firm].each_with_index do |sector, i|
        create(:partner, name: "Extra #{i}", sector: sector, verified_at: 1.day.ago)
      end

      get partners_path(lang: "fr")

      expect(response.body.scan(/class="partners-chip[^"]*is-extra/).size).to eq(2)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("main.partners.more_sectors", count: 2, locale: :fr)))
    end

    it "keeps the picked group's chip visible even past the limit" do
      %w[embassy hospital university mobile_carrier hotel law_firm].each_with_index do |sector, i|
        create(:partner, name: "Extra #{i}", sector: sector, verified_at: 1.day.ago)
      end

      get partners_path(lang: "fr", group: "telecom")

      expect(response.body).to match(/class="partners-chip is-active"[^>]*href="\/partners\?group=telecom/)
    end

    it "ignores an unknown group" do
      get partners_path(lang: "fr", group: "nope")

      expect(response.body).to include("CEP Test", "Banque Test")
    end
  end
end
