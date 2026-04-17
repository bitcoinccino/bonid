# frozen_string_literal: true

require "rails_helper"

# These specs exercise the presenter in isolation so we can catch the
# "mixed info" class of bugs — e.g. a scan row being colored like a
# transaction, a session event claiming :administrative, or a
# transaction's detail rows leaking into a consent.
#
# We use lightweight stand-ins (Struct / OpenStruct) for source records
# so each example is fast and independent of database schema drift.

RSpec.describe CitizenActivityEvent do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 4, 16, 14, 32) }

  # ------------------------------------------------------------
  # Helpers: lightweight record stand-ins
  # ------------------------------------------------------------
  def partner(name: "Bank Popilè", sector: "banking")
    OpenStruct.new(name: name, sector: sector)
  end

  def qr_scan_record(manual: false, city: "Pòtoprens", department_name: "Ouest")
    dept = department_name ? OpenStruct.new(name: department_name) : nil
    OpenStruct.new(manual: manual, city: city, department: dept)
  end

  def scan_log(overrides = {})
    OpenStruct.new({
      organization: "Bank Popilè",
      partner:      partner,
      qr_scan:      qr_scan_record,
      city:         "Pòtoprens",
      country:      "HT",
      region:       "Ouest",
      scanned_at:   now,
      created_at:   now
    }.merge(overrides))
  end

  def consent_grant(overrides = {})
    cg = OpenStruct.new({
      partner:           partner(name: "Zellus"),
      status:            "approved",
      requested_scopes:  %w[identity address],
      granted_scopes:    %w[identity],
      created_at:        now - 2.days,
      granted_at:        now - 2.days,
      revoked_at:        nil,
      expires_at:        now + 30.days,
      last_accessed_at:  now - 1.hour,
      access_count:      3
    }.merge(overrides))
    # `from_consent_grant` calls cg.status_theme — provide a minimal one.
    def cg.status_theme; { css: "success" }; end
    cg
  end

  def transaction_consent(overrides = {})
    OpenStruct.new({
      partner:          partner(name: "MonCash"),
      status:           "approved",
      amount:           5_000.0,
      currency:         "HTG",
      transaction_type: "payment",
      description:      "Peman sèvis elektrik",
      reference_id:     "REF-123",
      created_at:       now - 1.hour,
      decided_at:       now - 30.minutes,
      expires_at:       now + 10.minutes
    }.merge(overrides))
  end

  def service_application(overrides = {})
    sa = OpenStruct.new({
      partner:            partner(name: "DGI"),
      partner_schema:     OpenStruct.new(name: "Deklarasyon Revni"),
      status:             "submitted",
      verification_code:  "VER-999",
      paid:               true,
      submitted_at:       now - 3.days,
      reviewed_at:        nil,
      updated_at:         now - 3.days,
      rejection_reason:   nil,
      id:                 42
    }.merge(overrides))
    # Rails URL helpers call .to_param
    def sa.to_param; id.to_s; end
    sa
  end

  def citizen_session(overrides = {})
    OpenStruct.new({
      created_at:    now,
      ip_address:    "190.115.190.1",
      user_agent:    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
      city:          "Pòtoprens",
      country:       "HT",
      login_source:  "citizen_portal",
      device_type:   "mobile",
      new_device?:   false
    }.merge(overrides))
  end

  # ------------------------------------------------------------
  # Shape invariants — make sure each factory produces the right
  # kind and the right category. This is the exact class of bug
  # the user reported: a row showing up in the wrong tab/category.
  # ------------------------------------------------------------
  describe "kind/category invariants" do
    it "qr_scan → kind :scan, category :security" do
      ev = described_class.from_qr_scan(scan_log)
      expect(ev.kind).to eq(:scan)
      expect(ev.category).to eq(:security)
    end

    it "consent_grant → kind :consent, category :administrative" do
      ev = described_class.from_consent_grant(consent_grant)
      expect(ev.kind).to eq(:consent)
      expect(ev.category).to eq(:administrative)
    end

    it "transaction_consent → kind :transaction, category :financial" do
      ev = described_class.from_transaction_consent(transaction_consent)
      expect(ev.kind).to eq(:transaction)
      expect(ev.category).to eq(:financial)
    end

    it "service_application → kind :application, category :administrative" do
      ev = described_class.from_service_application(service_application)
      expect(ev.kind).to eq(:application)
      expect(ev.category).to eq(:administrative)
    end

    it "citizen_session → kind :session, category :security" do
      ev = described_class.from_session(citizen_session)
      expect(ev.kind).to eq(:session)
      expect(ev.category).to eq(:security)
    end
  end

  # ------------------------------------------------------------
  # from_qr_scan
  # ------------------------------------------------------------
  describe ".from_qr_scan" do
    it "uses the QR icon for camera scans and mentions the partner + location" do
      ev = described_class.from_qr_scan(scan_log)
      expect(ev.icon).to eq("ri-qr-scan-2-line")
      expect(ev.title).to include("Bank Popilè")
      expect(ev.title).to include("QR")
      expect(ev.title).to include("Pòtoprens")
    end

    it "uses the keyboard icon and '(manyèl)' title when the scan was entered manually" do
      log = scan_log(qr_scan: qr_scan_record(manual: true))
      ev = described_class.from_qr_scan(log)
      expect(ev.icon).to eq("ri-keyboard-box-line")
      expect(ev.title).to include("(manyèl)")
      expect(ev.title).not_to include("(QR)")
    end

    it "falls back to partner.name when organization is blank" do
      log = scan_log(organization: nil, partner: partner(name: "Digicel"))
      ev = described_class.from_qr_scan(log)
      expect(ev.title).to include("Digicel")
    end

    it "populates scan detail rows with partner/sector/method/location/date" do
      ev = described_class.from_qr_scan(scan_log)
      labels = ev.details.map(&:first)
      expect(labels).to include("Patnè", "Sektè", "Metòd", "Komin", "Depatman", "Peyi", "Dat egzak")
      expect(ev.details.to_h["Metòd"]).to eq("QR (eskan)")
    end

    it "does not leak consent-shaped detail rows (guard against mixed info)" do
      ev = described_class.from_qr_scan(scan_log)
      labels = ev.details.map(&:first)
      expect(labels).not_to include("Aksè bay", "Aksè mande", "Montan", "Kòd verifikasyon")
    end
  end

  # ------------------------------------------------------------
  # from_consent_grant
  # ------------------------------------------------------------
  describe ".from_consent_grant" do
    it "uses approved title + shield icon" do
      ev = described_class.from_consent_grant(consent_grant)
      expect(ev.icon).to eq("ri-shield-check-line")
      expect(ev.title).to include("Zellus")
      expect(ev.title).to start_with("Ou bay")
    end

    it "switches title + icon per status" do
      {
        "revoked" => { icon: "ri-forbid-2-line",   phrase: "Ou revoke aksè" },
        "pending" => { icon: "ri-time-line",       phrase: "mande aksè" },
        "expired" => { icon: "ri-history-line",    phrase: "ekspire" }
      }.each do |status, expected|
        ev = described_class.from_consent_grant(consent_grant(status: status))
        expect(ev.icon).to eq(expected[:icon]), "wrong icon for #{status}"
        expect(ev.title).to include(expected[:phrase]), "wrong title for #{status}"
      end
    end

    it "shows granted scopes (truncated) in the subtitle" do
      cg = consent_grant(granted_scopes: %w[identity address phone email])
      ev = described_class.from_consent_grant(cg)
      expect(ev.subtitle).to start_with("Aksè:")
      expect(ev.subtitle).to end_with("…") # > 3 scopes triggers the ellipsis
    end

    it "populates consent detail rows with scopes and timestamps" do
      ev = described_class.from_consent_grant(consent_grant)
      rows = ev.details.to_h
      expect(rows["Patnè"]).to eq("Zellus")
      expect(rows["Aksè mande"]).to eq("identity, address")
      expect(rows["Aksè bay"]).to eq("identity")
      expect(rows["Kantite aksè"]).to eq("3")
      expect(rows.keys).to include("Kreye", "Bay", "Ekspire", "Dènye aksè")
    end

    it "drops blank rows (no 'Revoke' when it never happened)" do
      ev = described_class.from_consent_grant(consent_grant)
      expect(ev.details.map(&:first)).not_to include("Revoke")
    end
  end

  # ------------------------------------------------------------
  # from_transaction_consent
  # ------------------------------------------------------------
  describe ".from_transaction_consent" do
    it "shows the approved-amount title with formatted amount + partner" do
      ev = described_class.from_transaction_consent(transaction_consent)
      expect(ev.icon).to eq("ri-exchange-funds-line")
      expect(ev.title).to include("MonCash")
      expect(ev.title).to include("5,000 HTG")
      expect(ev.title).to start_with("Ou apwouve")
    end

    it "uses 'Ou refize' for denied and 'mande' for pending" do
      denied  = described_class.from_transaction_consent(transaction_consent(status: "denied"))
      pending = described_class.from_transaction_consent(transaction_consent(status: "pending"))
      expect(denied.title).to start_with("Ou refize")
      expect(pending.title).to include("mande")
    end

    it "omits the currency when amount is blank/zero" do
      ev = described_class.from_transaction_consent(transaction_consent(amount: 0))
      expect(ev.title).not_to include("HTG")
    end

    it "populates transaction detail rows with money + reference + dates" do
      ev = described_class.from_transaction_consent(transaction_consent)
      rows = ev.details.to_h
      expect(rows["Patnè"]).to eq("MonCash")
      expect(rows["Montan"]).to eq("5,000 HTG")
      expect(rows["Kalite"]).to eq("Payment")
      expect(rows["Deskripsyon"]).to eq("Peman sèvis elektrik")
      expect(rows["Referans"]).to eq("REF-123")
    end

    it "never returns consent-only fields (guard against mixed info)" do
      ev = described_class.from_transaction_consent(transaction_consent)
      expect(ev.details.map(&:first)).not_to include("Aksè bay", "Aksè mande", "Kòd verifikasyon")
    end
  end

  # ------------------------------------------------------------
  # from_service_application
  # ------------------------------------------------------------
  describe ".from_service_application" do
    it "uses a status-appropriate title per state" do
      {
        "draft"        => "bouyon",
        "submitted"    => "soumèt yon aplikasyon",
        "under_review" => "ap revize",
        "approved"     => "apwouve",
        "rejected"     => "rejte",
        "cancelled"    => "anile"
      }.each do |status, phrase|
        ev = described_class.from_service_application(service_application(status: status))
        expect(ev.title.downcase).to include(phrase), "wrong title for #{status}"
      end
    end

    it "populates application detail rows with form name + code + paid flag" do
      ev = described_class.from_service_application(service_application)
      rows = ev.details.to_h
      expect(rows["Patnè"]).to eq("DGI")
      expect(rows["Fòm"]).to eq("Deklarasyon Revni")
      expect(rows["Kòd verifikasyon"]).to eq("VER-999")
      expect(rows["Peye"]).to eq("Wi")
      expect(rows["Statè"]).to eq("Submitted")
    end

    it "renders paid=false as 'Non'" do
      ev = described_class.from_service_application(service_application(paid: false))
      expect(ev.details.to_h["Peye"]).to eq("Non")
    end

    it "never returns scan-only or transaction-only fields" do
      ev = described_class.from_service_application(service_application)
      labels = ev.details.map(&:first)
      expect(labels).not_to include("Metòd", "Komin", "Montan", "Referans")
    end
  end

  # ------------------------------------------------------------
  # from_session
  # ------------------------------------------------------------
  describe ".from_session" do
    it "uses the regular login title + icon for familiar devices" do
      ev = described_class.from_session(citizen_session, new_device: false)
      expect(ev.icon).to eq("ri-login-box-line")
      expect(ev.title).to eq("Ou konekte sou BonID ou")
      expect(ev.status_color).to eq("secondary")
    end

    it "uses an alert title + icon + warning color for a new device" do
      ev = described_class.from_session(citizen_session, new_device: true)
      expect(ev.icon).to eq("ri-alert-line")
      expect(ev.title).to include("Nouvo aparèy")
      expect(ev.status_color).to eq("warning")
    end

    it "populates session detail rows with device, IP, and location" do
      ev = described_class.from_session(citizen_session, new_device: false)
      rows = ev.details.to_h
      expect(rows["Aparèy"]).to eq("Mobile")
      expect(rows["Adrès IP"]).to eq("190.115.190.1")
      expect(rows["Vil"]).to eq("Pòtoprens")
      expect(rows["Peyi"]).to eq("HT")
      expect(rows["Navigatè"]).to include("iPhone")
    end

    it "has no deep_link (session rows don't link anywhere)" do
      ev = described_class.from_session(citizen_session, new_device: false)
      expect(ev.deep_link).to be_nil
    end

    it "falls back to cs.new_device? when the keyword is not passed" do
      cs = citizen_session
      allow(cs).to receive(:new_device?).and_return(true)
      ev = described_class.from_session(cs) # no keyword
      expect(ev.title).to include("Nouvo aparèy")
    end
  end

  # ------------------------------------------------------------
  # details: blanks are always dropped regardless of kind
  # ------------------------------------------------------------
  describe "#details blank filtering" do
    it "drops rows whose value is nil or empty string" do
      cg = consent_grant(granted_at: nil, revoked_at: nil, expires_at: nil,
                         last_accessed_at: nil, access_count: 0)
      ev  = described_class.from_consent_grant(cg)
      labels = ev.details.map(&:first)
      expect(labels).not_to include("Bay", "Revoke", "Ekspire", "Dènye aksè", "Kantite aksè")
      expect(labels).to include("Patnè", "Statè", "Kreye")
    end
  end

  # ------------------------------------------------------------
  # timestamp_label / full_timestamp / date_bucket
  # ------------------------------------------------------------
  describe "time formatting" do
    around do |ex|
      Time.use_zone("UTC") { travel_to(Time.zone.local(2026, 4, 16, 18, 0)) { ex.run } }
    end

    def ev_at(t)
      described_class.new(kind: :session, source_record: OpenStruct.new, timestamp: t,
                           icon: "x", title: "t")
    end

    it "renders today as 'Jodi a a HH:MM'" do
      expect(ev_at(Time.zone.local(2026, 4, 16, 10, 45)).timestamp_label).to eq("Jodi a a 10:45")
    end

    it "renders yesterday as 'Yè a HH:MM'" do
      expect(ev_at(Time.zone.local(2026, 4, 15, 14, 20)).timestamp_label).to eq("Yè a 14:20")
    end

    it "renders 2-6 days ago as 'N jou de sa'" do
      expect(ev_at(3.days.ago).timestamp_label).to eq("3 jou de sa")
    end

    it "renders older same-year events as '15 Me' (day + HT month)" do
      expect(ev_at(Time.zone.local(2026, 5, 15, 12, 0)).timestamp_label).to eq("15 Me")
    end

    it "renders cross-year events with the year included" do
      expect(ev_at(Time.zone.local(2024, 5, 15, 12, 0)).timestamp_label).to eq("15 Me 2024")
    end

    it "full_timestamp is an absolute label with HT month" do
      ev = ev_at(Time.zone.local(2026, 3, 30, 14, 32))
      expect(ev.full_timestamp).to eq("30 Mas 2026 a 14:32")
    end

    it "date_bucket returns :today / :yesterday symbols" do
      expect(ev_at(Time.zone.local(2026, 4, 16, 10, 0)).date_bucket).to eq(:today)
      expect(ev_at(Time.zone.local(2026, 4, 15, 10, 0)).date_bucket).to eq(:yesterday)
      expect(ev_at(Time.zone.local(2026, 3, 1, 10, 0)).date_bucket).to be_a(Date)
    end
  end
end
