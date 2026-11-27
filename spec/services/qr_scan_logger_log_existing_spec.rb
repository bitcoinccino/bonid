# frozen_string_literal: true

require "rails_helper"

# The partner portal and agent "Scan / Look up BonID" pages save their own
# QrScan. The citizen's bell and scan alert read QrScanLog, so those checks
# must also write the log (QrScanLogger.log_existing!), or the citizen
# never hears about them.
RSpec.describe QrScanLogger, ".log_existing!" do
  include ActiveJob::TestHelper

  let(:citizen)    { create(:user, :with_address, preferred_locale: "en") }
  let(:submission) { create(:identity_submission, :approved, user: citizen) }
  let(:partner)    { create(:partner, :approved, name: "Unibank", sector: "commercial_bank") }

  def partner_scan
    submission.qr_scans.create!(identity_submission: submission, partner: partner, verified_by: "Partner",
                                manual: true, scanned_at: Time.current, ip_address: "1.2.3.4",
                                user_agent: "RSpec", city: "Cap-Haïtien", country: "Haiti")
  end

  it "writes the audit log for the scan" do
    scan = partner_scan
    log = described_class.log_existing!(scan, source: "partner_scan")

    expect(log).to be_persisted
    expect(log).to have_attributes(qr_scan: scan, identity_submission: submission, partner: partner,
                                   source: "partner_scan", ip_address: "1.2.3.4")
  end

  it "emails the citizen" do
    expect { described_class.log_existing!(partner_scan, source: "partner_scan") }
      .to have_enqueued_mail(Citizens::QrScanMailer, :scan_alert)
  end

  it "rings the citizen's bell" do
    citizen.update!(notifications_seen_at: 1.day.ago)
    expect { described_class.log_existing!(partner_scan, source: "partner_scan") }
      .to change { Citizens::AlertCounter.new(citizen.reload).total }.by(1)
    expect(Citizens::AlertCounter.new(citizen).recent_events(limit: 1).first.title).to include("Unibank")
  end

  it "never raises, so a paid lookup still completes" do
    scan = partner_scan
    allow(QrScanLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect(described_class.log_existing!(scan, source: "partner_scan")).to be_nil
  end
end
