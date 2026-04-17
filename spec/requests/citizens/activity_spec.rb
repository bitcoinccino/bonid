# frozen_string_literal: true

require "rails_helper"

# These specs target the exact behaviors the citizen reported mixed
# output for:
#   • pill counts must match what the list actually shows (no "5" on a
#     pill that renders empty)
#   • date window must apply consistently to counts AND list
#   • category filter must apply to counts too, or pills mislead users
#     (e.g. Koneksyon=2 while Administratif filter hides all sessions)
#   • each tab must dispatch to the right loader — the scans tab must
#     never render a consent row, etc.

RSpec.describe "Citizens::Activity", type: :request do
  include Devise::Test::IntegrationHelpers

  before(:all) do
    Devise.mappings[:user] = Devise.mappings[:citizen]
  end

  let!(:citizen)      { create(:user) }
  let!(:other_partner) { create(:partner) }

  before { sign_in citizen, scope: :citizen }

  # ------------------------------------------------------------
  # Tiny builders — use Model.create! directly so we don't depend
  # on factories we don't control.
  # ------------------------------------------------------------
  def make_session(at:, ip: "1.1.1.1", fp: "dev-#{SecureRandom.hex(4)}")
    CitizenSession.create!(
      user:               citizen,
      otp_digest:         BCrypt::Password.create("123456"),
      expires_at:         at + 10.minutes,
      ip_address:         ip,
      device_fingerprint: fp,
      login_source:       "citizen_portal",
      user_agent:         "Mozilla/5.0 Test",
      city:               "Pòtoprens",
      country:            "HT",
      created_at:         at,
      updated_at:         at
    )
  end

  def make_consent(at:, status: :approved, partner: other_partner)
    cg = ConsentGrant.create!(
      citizen:           citizen,
      partner:           partner,
      grant_token:       SecureRandom.hex(16),
      requested_scopes:  %w[identity],
      granted_scopes:    %w[identity],
      status:            status,
      created_at:        at,
      updated_at:        at
    )
    cg.update_columns(created_at: at, updated_at: at) # bypass touch
    cg
  end

  # ------------------------------------------------------------
  # Smoke
  # ------------------------------------------------------------
  describe "GET /citizens/activity" do
    it "renders successfully for a signed-in citizen" do
      get citizens_activity_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aktivite")
    end

    it "redirects unauthenticated visitors" do
      sign_out citizen
      get citizens_activity_path
      expect(response).to have_http_status(:redirect)
    end
  end

  # ------------------------------------------------------------
  # Pill counts / date window
  # ------------------------------------------------------------
  describe "pill counts" do
    before do
      # In-window
      make_session(at: 2.days.ago,  ip: "1.1.1.1")
      make_session(at: 5.days.ago,  ip: "1.1.1.2")
      # Outside the default 30-day window
      make_session(at: 60.days.ago, ip: "9.9.9.9")

      # One admin-category event in-window
      make_consent(at: 1.day.ago)
    end

    it "counts only in-window sessions by default (30-day window)" do
      get citizens_activity_path
      pill = session_pill(response.body)
      expect(pill).to eq("2"), "expected 2 in-window sessions, got #{pill.inspect}"
    end

    it "counts activity outside the default window when the range is widened" do
      get citizens_activity_path, params: { from: 90.days.ago.to_date.to_s, to: Date.current.to_s }
      expect(session_pill(response.body)).to eq("3")
    end

    it "hides security pills when Administratif filter is active (fixes Koneksyon=2 bug)" do
      get citizens_activity_path, params: { filter: "administrative" }
      # Koneksyon pill should disappear — not show the raw session count
      expect(session_pill(response.body)).to be_nil
      # Konsantman pill should show 1 (the approved consent is administrative)
      expect(consents_pill(response.body)).to eq("1")
    end

    it "hides administrative pills when Sekirite filter is active" do
      get citizens_activity_path, params: { filter: "security" }
      expect(session_pill(response.body)).to eq("2")
      expect(consents_pill(response.body)).to be_nil
    end

    it "hides security + administrative pills when Finansye is active" do
      get citizens_activity_path, params: { filter: "financial" }
      expect(session_pill(response.body)).to be_nil
      expect(consents_pill(response.body)).to be_nil
    end
  end

  # ------------------------------------------------------------
  # Tab dispatch — the right rows land in the right tab
  # ------------------------------------------------------------
  describe "tab dispatch" do
    before do
      make_session(at: 2.days.ago)
      make_consent(at: 1.day.ago)
    end

    it "sessions tab renders session rows and no consent rows" do
      get citizens_activity_path, params: { tab: "sessions" }
      expect(response.body).to include("Ou konekte sou BonID ou")
                          .or  include("Nouvo aparèy konekte sou BonID ou")
      expect(response.body).not_to include("Ou bay") # consent-approved phrasing
    end

    it "consents tab renders consent rows and no session rows" do
      get citizens_activity_path, params: { tab: "consents" }
      expect(response.body).to include("Ou bay")
      expect(response.body).not_to include("konekte sou BonID")
    end

    it "sessions tab renders empty state + period hint when the filter masks all sessions" do
      get citizens_activity_path, params: { tab: "sessions", filter: "administrative" }
      expect(response.body).to include("Okenn koneksyon poko anrejistre")
      expect(response.body).to include("Agrandi peryòd la")
    end
  end

  # ------------------------------------------------------------
  # Expandable detail panel — the row's <details> summary mentions
  # the right source-specific fields (fights against "mix info")
  # ------------------------------------------------------------
  describe "detail panel" do
    it "session rows include IP + device + Haitian Creole field labels" do
      make_session(at: 1.hour.ago, ip: "190.115.190.42")
      get citizens_activity_path, params: { tab: "sessions" }
      expect(response.body).to include("190.115.190.42")
      expect(response.body).to include("Aparèy")
      expect(response.body).to include("Adrès IP")
    end

    it "consent rows include scope labels, not session fields" do
      make_consent(at: 2.hours.ago)
      get citizens_activity_path, params: { tab: "consents" }
      expect(response.body).to include("Aksè mande")
      expect(response.body).not_to include("Adrès IP")
    end
  end

  # ------------------------------------------------------------
  # Helpers: tolerate the HTML structure without coupling tightly
  # ------------------------------------------------------------
  # The pill markup for each tab looks like:
  #   <a ... class="activity-tab ..."><i class="icon"></i>
  #     <span class="activity-tab-label">Koneksyon</span>
  #     <span class="activity-tab-count">2</span>
  #   </a>
  # We grab the tab anchor by label text, then pull the count span
  # out of it (returning nil when the badge is absent — the view
  # suppresses it for zero).
  # ------------------------------------------------------------
  def pill_count_for(html, label)
    doc  = Nokogiri::HTML(html)
    tab  = doc.css("a.activity-tab").find { |a| a.css(".activity-tab-label").text.strip == label }
    return nil unless tab
    count = tab.at_css(".activity-tab-count")
    count&.text&.strip
  end

  def session_pill(html);  pill_count_for(html, "Koneksyon"); end
  def consents_pill(html); pill_count_for(html, "Konsantman"); end
end
