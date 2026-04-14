# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamInvitationService do
  let(:partner) { create(:partner, :verified, sector: "dgi") }
  let(:admin_user) do
    user = create(:user)
    user.add_role(:partner_admin)
    user.update!(partner: partner)
    user
  end

  # Create a verified invitee (approved BonID)
  let(:invitee) do
    user = create(:user, email: "invitee-#{SecureRandom.hex(4)}@bonid.ht")
    allow_any_instance_of(IdentitySubmission).to receive(:auto_link_verified_user_to_officer)
    allow_any_instance_of(IdentitySubmission).to receive(:ensure_user_bonid_and_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:regenerate_combined_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:generate_secure_qr_if_approved)
    allow_any_instance_of(IdentitySubmission).to receive(:copy_selfie_to_user_photo)
    create(:identity_submission, :approved, user: user, bonid: user.bonid)
    user
  end

  before do
    # Prevent actual email delivery
    allow(TeamMailer).to receive_message_chain(:invitation, :deliver_later)
    # Stub Current.request for audit log IP
    allow(Current).to receive(:request).and_return(nil)
  end

  # ── .call (invite flow) ─────────────────────────────────────
  describe ".call" do
    it "invites a verified BonID user as partner_agent" do
      bonid_suffix = invitee.bonid.delete("-").last(6)
      result = described_class.call(
        partner: partner, bonid: bonid_suffix, role: "partner_agent",
        invited_by: admin_user
      )
      expect(result.success?).to be true
      expect(result.user).to eq(invitee)
      expect(invitee.reload.partner_id).to eq(partner.id)
      expect(invitee.has_role?(:partner_agent)).to be true
      expect(invitee.invitation_sent_at).to be_present
    end

    it "rejects an invalid role for the sector" do
      bonid_suffix = invitee.bonid.delete("-").last(6)
      result = described_class.call(
        partner: partner, bonid: bonid_suffix, role: "bank_teller",
        invited_by: admin_user
      )
      expect(result.success?).to be false
      expect(result.error).to include("pa valid")
    end

    it "rejects a blank BonID" do
      result = described_class.call(
        partner: partner, bonid: "", role: "partner_agent",
        invited_by: admin_user
      )
      expect(result.success?).to be false
      expect(result.error).to include("BonID obligatwa")
    end

    it "rejects an unknown BonID" do
      result = described_class.call(
        partner: partner, bonid: "ZZZZZZ", role: "partner_agent",
        invited_by: admin_user
      )
      expect(result.success?).to be false
      expect(result.error).to include("Pa gen moun")
    end

    it "rejects self-invitation" do
      # Admin needs an approved identity submission to pass the verification gate
      allow_any_instance_of(IdentitySubmission).to receive(:auto_link_verified_user_to_officer)
      allow_any_instance_of(IdentitySubmission).to receive(:ensure_user_bonid_and_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:regenerate_combined_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:generate_secure_qr_if_approved)
      allow_any_instance_of(IdentitySubmission).to receive(:copy_selfie_to_user_photo)
      create(:identity_submission, :approved, user: admin_user, bonid: admin_user.bonid)

      bonid_suffix = admin_user.bonid.delete("-").last(6)
      result = described_class.call(
        partner: partner, bonid: bonid_suffix, role: "partner_agent",
        invited_by: admin_user
      )
      expect(result.success?).to be false
      expect(result.error).to include("tèt ou")
    end

    it "rejects duplicate role assignment" do
      bonid_suffix = invitee.bonid.delete("-").last(6)
      # First invite
      described_class.call(
        partner: partner, bonid: bonid_suffix, role: "partner_agent",
        invited_by: admin_user
      )
      # Second invite with same role
      result = described_class.call(
        partner: partner, bonid: bonid_suffix, role: "partner_agent",
        invited_by: admin_user
      )
      expect(result.success?).to be false
      expect(result.error).to include("deja nan ekip")
    end

    it "creates an audit log entry" do
      bonid_suffix = invitee.bonid.delete("-").last(6)
      expect {
        described_class.call(
          partner: partner, bonid: bonid_suffix, role: "partner_agent",
          invited_by: admin_user
        )
      }.to change(PartnerAuditLog, :count).by(1)

      log = PartnerAuditLog.last
      expect(log.event).to eq("team_invitation_sent")
      expect(log.details).to include("partner_agent")
    end

    context "with ONACA sector" do
      let(:onaca_partner) { create(:partner, :verified, sector: "onaca") }
      let(:onaca_admin) do
        user = create(:user, email: "onaca-admin-#{SecureRandom.hex(4)}@bonid.ht")
        user.add_role(:partner_admin)
        user.update!(partner: onaca_partner)
        user
      end

      it "accepts partner_agent_surveyor role" do
        bonid_suffix = invitee.bonid.delete("-").last(6)
        result = described_class.call(
          partner: onaca_partner, bonid: bonid_suffix, role: "partner_agent_surveyor",
          invited_by: onaca_admin
        )
        expect(result.success?).to be true
        expect(invitee.reload.has_role?(:partner_agent_surveyor)).to be true
      end

      it "accepts partner_agent_notary role" do
        bonid_suffix = invitee.bonid.delete("-").last(6)
        result = described_class.call(
          partner: onaca_partner, bonid: bonid_suffix, role: "partner_agent_notary",
          invited_by: onaca_admin
        )
        expect(result.success?).to be true
        expect(invitee.reload.has_role?(:partner_agent_notary)).to be true
      end

      it "rejects partner_agent (not valid for ONACA)" do
        bonid_suffix = invitee.bonid.delete("-").last(6)
        result = described_class.call(
          partner: onaca_partner, bonid: bonid_suffix, role: "partner_agent",
          invited_by: onaca_admin
        )
        expect(result.success?).to be false
        expect(result.error).to include("pa valid")
      end
    end

    context "with banking sector" do
      let(:bank_partner) { create(:partner, :verified, sector: "commercial_bank") }
      let(:bank_admin) do
        user = create(:user, email: "bank-admin-#{SecureRandom.hex(4)}@bonid.ht")
        user.add_role(:partner_admin)
        user.update!(partner: bank_partner)
        user
      end

      it "accepts bank_agent role" do
        bonid_suffix = invitee.bonid.delete("-").last(6)
        result = described_class.call(
          partner: bank_partner, bonid: bonid_suffix, role: "bank_agent",
          invited_by: bank_admin
        )
        expect(result.success?).to be true
        expect(invitee.reload.has_role?(:bank_agent)).to be true
      end

      it "accepts bank_teller role" do
        bonid_suffix = invitee.bonid.delete("-").last(6)
        result = described_class.call(
          partner: bank_partner, bonid: bonid_suffix, role: "bank_teller",
          invited_by: bank_admin
        )
        expect(result.success?).to be true
        expect(invitee.reload.has_role?(:bank_teller)).to be true
      end

      it "accepts bank_supervisor role" do
        bonid_suffix = invitee.bonid.delete("-").last(6)
        result = described_class.call(
          partner: bank_partner, bonid: bonid_suffix, role: "bank_supervisor",
          invited_by: bank_admin
        )
        expect(result.success?).to be true
        expect(invitee.reload.has_role?(:bank_supervisor)).to be true
      end

      it "rejects partner_agent (not valid for banking)" do
        bonid_suffix = invitee.bonid.delete("-").last(6)
        result = described_class.call(
          partner: bank_partner, bonid: bonid_suffix, role: "partner_agent",
          invited_by: bank_admin
        )
        expect(result.success?).to be false
        expect(result.error).to include("pa valid")
      end
    end
  end

  # ── .lookup ─────────────────────────────────────────────────
  describe ".lookup" do
    it "returns user info for a valid BonID suffix" do
      bonid_suffix = invitee.bonid.delete("-").last(6)
      result = described_class.lookup(bonid_suffix)
      expect(result).to be_a(Hash)
      expect(result[:full_name]).to eq(invitee.full_name)
      expect(result[:bonid]).to eq(invitee.bonid)
      expect(result[:verified]).to be true
    end

    it "masks the email" do
      bonid_suffix = invitee.bonid.delete("-").last(6)
      result = described_class.lookup(bonid_suffix)
      expect(result[:email]).to include("*")
      expect(result[:email]).not_to eq(invitee.email)
    end

    it "returns nil for unknown BonID" do
      expect(described_class.lookup("ZZZZZZ")).to be_nil
    end

    it "returns nil for blank input" do
      expect(described_class.lookup("")).to be_nil
    end
  end

  # ── .mask_email ─────────────────────────────────────────────
  describe ".mask_email" do
    it "masks the local part" do
      expect(described_class.mask_email("jean.louis@bonid.ht")).to eq("je****@bonid.ht")
    end

    it "returns nil for blank" do
      expect(described_class.mask_email("")).to be_nil
    end

    it "returns short emails unchanged" do
      expect(described_class.mask_email("ab@x.com")).to eq("ab@x.com")
    end
  end
end
