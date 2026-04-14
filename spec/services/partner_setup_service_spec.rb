# frozen_string_literal: true

require "rails_helper"

RSpec.describe PartnerSetupService do
  let(:admin_user) { create(:admin_user) }
  let(:partner) { create(:partner, email: "partner-test-#{SecureRandom.hex(4)}@example.com", sector: "healthcare") }
  let(:service) { described_class.new(partner: partner, admin_user: admin_user) }

  before do
    # Prevent route generation and mailer calls
    allow_any_instance_of(PartnerSetupService).to receive(:send_invite_email)
  end

  # ── Approve ──────────────────────────────────────────────────
  describe "#approve!" do
    it "activates and verifies the partner" do
      result = service.approve!
      expect(result).to be true
      partner.reload
      expect(partner.verified_at).to be_present
      expect(partner.active).to be true
      expect(partner.status).to eq("approved")
    end

    it "generates an API key if none exists" do
      partner.update_column(:api_key_digest, nil)
      service.approve!
      expect(partner.reload.api_key_digest).to be_present
    end

    it "creates a partner admin user account" do
      service.approve!
      user = User.find_by(email: partner.email)
      expect(user).to be_present
      expect(user.partner).to eq(partner)
      expect(user.has_role?(:partner_admin)).to be true
    end

    it "does not create a teller for non-banking partners" do
      partner.update!(sector: "healthcare")
      service.approve!
      teller = User.find_by(email: "agent@#{partner.slug}.ht")
      expect(teller).to be_nil
    end
  end

  # ── Reject ───────────────────────────────────────────────────
  describe "#reject!" do
    it "rejects the partner with a reason" do
      result = service.reject!(reason: "incomplete_application")
      expect(result).to be true
      partner.reload
      expect(partner.status).to eq("rejected")
      expect(partner.active).to be false
      expect(partner.verified_at).to be_nil
      expect(partner.rejection_reason).to eq("incomplete_application")
    end

    it "creates an audit log entry" do
      expect {
        service.reject!(reason: "incomplete_application", comment: "Missing NIF")
      }.to change(PartnerAuditLog, :count).by(1)

      log = PartnerAuditLog.last
      expect(log.event).to eq("partner_rejected")
      # details is a text column storing serialized Ruby hash
      expect(log.details).to include("incomplete_application")
      expect(log.details).to include("Missing NIF")
    end
  end
end
