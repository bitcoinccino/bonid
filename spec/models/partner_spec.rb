# frozen_string_literal: true

require "rails_helper"

RSpec.describe Partner, type: :model do
  # ── Associations ─────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to have_many(:users).dependent(:nullify) }
    it { is_expected.to have_many(:identity_submissions).dependent(:nullify) }
    it { is_expected.to have_many(:verification_records).dependent(:nullify) }
    it { is_expected.to have_many(:partner_audit_logs).dependent(:nullify) }
    it { is_expected.to have_many(:partner_branches).dependent(:destroy) }
    it { is_expected.to have_many(:partner_schemas).dependent(:destroy) }
    it { is_expected.to have_many(:partner_api_logs).dependent(:destroy) }
    it { is_expected.to have_many(:credit_ledger_entries).dependent(:destroy) }
    it { is_expected.to have_one(:address) }
    it { is_expected.to belong_to(:admin_user).optional }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:slug) }

    it "validates webhook_url is HTTPS" do
      partner = build(:partner, webhook_url: "http://insecure.com/webhook")
      expect(partner).not_to be_valid
      expect(partner.errors[:webhook_url]).to include("must be HTTPS")
    end

    it "allows blank webhook_url" do
      partner = build(:partner, webhook_url: nil)
      partner.valid?
      expect(partner.errors[:webhook_url]).to be_empty
    end
  end

  # ── Enums ────────────────────────────────────────────────────
  describe "enums" do
    it "defines status enum with suffix" do
      expect(Partner.statuses).to eq("pending" => 0, "approved" => 1, "rejected" => 2, "suspended" => 3)
    end
  end

  # ── Scopes ───────────────────────────────────────────────────
  describe "scopes" do
    let!(:active_partner) { create(:partner, :verified, active: true) }
    let!(:inactive_partner) { create(:partner, active: false) }

    it ".active returns active partners" do
      expect(described_class.active).to include(active_partner)
      expect(described_class.active).not_to include(inactive_partner)
    end

    it ".verified returns verified partners" do
      expect(described_class.verified).to include(active_partner)
    end
  end

  # ── API Key System ──────────────────────────────────────────
  describe "API key system" do
    let(:partner) { create(:partner) }

    describe ".find_by_api_key" do
      it "finds partner by raw API key" do
        raw_key = partner.raw_api_key
        # The factory uses BCrypt, but Partner model uses SHA256
        # Set up with SHA256 digest to match production behavior
        digest = OpenSSL::Digest::SHA256.hexdigest(raw_key)
        partner.update_column(:api_key_digest, digest)

        found = Partner.find_by_api_key(raw_key)
        expect(found).to eq(partner)
      end

      it "returns nil for invalid key" do
        expect(Partner.find_by_api_key("fake_key")).to be_nil
      end

      it "returns nil for blank key" do
        expect(Partner.find_by_api_key(nil)).to be_nil
        expect(Partner.find_by_api_key("")).to be_nil
      end
    end

    describe "#rotate_api_key!" do
      it "generates a new API key" do
        old_digest = partner.api_key_digest
        partner.rotate_api_key!
        expect(partner.api_key_digest).not_to eq(old_digest)
        expect(partner.generated_api_key).to start_with("bonid_live_")
      end
    end
  end

  # ── Security Signing ────────────────────────────────────────
  describe "payload signing" do
    let(:partner) { create(:partner) }
    let(:payload) { { bonid: "VP-1990-M-OU-P1234-ABCD", action: "verify" } }

    describe "#sign_payload" do
      it "generates HMAC-SHA256 signature" do
        sig = partner.sign_payload(payload)
        expect(sig).to be_a(String)
        expect(sig.length).to eq(64)
      end
    end

    describe "#verify_signature" do
      it "verifies a valid signature" do
        sig = partner.sign_payload(payload)
        expect(partner.verify_signature(payload, sig)).to be true
      end

      it "rejects tampered payload" do
        sig = partner.sign_payload(payload)
        tampered = payload.merge(action: "delete")
        expect(partner.verify_signature(tampered, sig)).to be false
      end
    end
  end

  # ── Webhook ─────────────────────────────────────────────────
  describe "webhook" do
    describe "#webhook_enabled?" do
      it "returns true when URL and verified" do
        partner = build(:partner, webhook_url: "https://example.com/hook", verified_at: Time.current)
        expect(partner.webhook_enabled?).to be true
      end

      it "returns false without URL" do
        partner = build(:partner, webhook_url: nil, verified_at: Time.current)
        expect(partner.webhook_enabled?).to be false
      end

      it "returns false when unverified" do
        partner = build(:partner, webhook_url: "https://example.com/hook", verified_at: nil)
        expect(partner.webhook_enabled?).to be false
      end
    end
  end

  # ── Email Verification ──────────────────────────────────────
  describe "email verification" do
    let(:partner) { create(:partner) }

    describe "#verify_email!" do
      it "sets email_verified_at and clears token" do
        partner.verify_email!
        expect(partner.email_verified_at).to be_present
        expect(partner.email_verification_token).to be_nil
      end
    end

    describe "#email_verified?" do
      it "returns false before verification" do
        expect(partner.email_verified?).to be false
      end

      it "returns true after verification" do
        partner.verify_email!
        expect(partner.email_verified?).to be true
      end
    end
  end

  # ── OAuth ───────────────────────────────────────────────────
  describe "OAuth" do
    describe "#valid_redirect_uri?" do
      let(:partner) { build(:partner, redirect_uris: ["https://app.example.com/callback"]) }

      it "validates registered URIs" do
        expect(partner.valid_redirect_uri?("https://app.example.com/callback")).to be true
      end

      it "rejects unregistered URIs" do
        expect(partner.valid_redirect_uri?("https://evil.com/steal")).to be false
      end

      it "returns false for blank URI" do
        expect(partner.valid_redirect_uri?(nil)).to be false
      end
    end

    describe "#scope_allowed?" do
      it "allows all scopes when no restrictions" do
        partner = build(:partner, allowed_scopes: nil)
        expect(partner.scope_allowed?("identity:verify")).to be true
      end

      it "checks against allowed scopes" do
        partner = build(:partner, allowed_scopes: ["identity:verify"])
        expect(partner.scope_allowed?("identity:verify")).to be true
        expect(partner.scope_allowed?("crime:full")).to be false
      end
    end
  end

  # ── Credit System ───────────────────────────────────────────
  describe "credit system" do
    let(:partner) { create(:partner, credit_balance: 1000) }

    it "starts with assigned credits" do
      expect(partner.credit_balance).to eq(1000)
    end
  end
end
