# frozen_string_literal: true

require "rails_helper"

RSpec.describe OneTimeSecret do
  let(:partner) { create(:partner, :approved) }

  # ─────────────────────────────────────────────────────────
  # .create_for
  # ─────────────────────────────────────────────────────────
  describe ".create_for" do
    it "creates an encrypted secret with a unique token" do
      secret = described_class.create_for(
        partner: partner,
        payload: { client_id: "abc", client_secret: "xyz" }
      )

      expect(secret).to be_persisted
      expect(secret.token).to be_present
      expect(secret.encrypted_payload).not_to include("xyz")
      expect(secret.expires_at).to be > 23.hours.from_now
      expect(secret.viewed_at).to be_nil
    end

    it "accepts custom expiration" do
      secret = described_class.create_for(
        partner: partner,
        payload: { key: "val" },
        expires_in: 1.hour
      )

      expect(secret.expires_at).to be < 2.hours.from_now
    end
  end

  # ─────────────────────────────────────────────────────────
  # #reveal!
  # ─────────────────────────────────────────────────────────
  describe "#reveal!" do
    let(:secret) do
      described_class.create_for(
        partner: partner,
        payload: { client_id: "id-123", client_secret: "secret-456" }
      )
    end

    it "decrypts and returns the payload on first view" do
      result = secret.reveal!(ip_address: "1.2.3.4")

      expect(result["client_id"]).to eq("id-123")
      expect(result["client_secret"]).to eq("secret-456")
      expect(secret.viewed_at).to be_present
      expect(secret.viewed_ip).to eq("1.2.3.4")
    end

    it "returns nil on second view" do
      secret.reveal!(ip_address: "1.2.3.4")
      result = secret.reveal!(ip_address: "5.6.7.8")

      expect(result).to be_nil
    end

    it "returns nil when expired" do
      secret.update_column(:expires_at, 1.hour.ago)

      expect(secret.reveal!).to be_nil
    end
  end

  # ─────────────────────────────────────────────────────────
  # #available?
  # ─────────────────────────────────────────────────────────
  describe "#available?" do
    let(:secret) do
      described_class.create_for(partner: partner, payload: { a: 1 })
    end

    it "is true when fresh" do
      expect(secret).to be_available
    end

    it "is false after viewing" do
      secret.reveal!
      expect(secret).not_to be_available
    end

    it "is false after expiry" do
      secret.update_column(:expires_at, 1.minute.ago)
      expect(secret).not_to be_available
    end
  end

  # ─────────────────────────────────────────────────────────
  # .available scope
  # ─────────────────────────────────────────────────────────
  describe ".available scope" do
    it "excludes viewed and expired secrets" do
      fresh = described_class.create_for(partner: partner, payload: { a: 1 })
      viewed = described_class.create_for(partner: partner, payload: { b: 2 })
      viewed.reveal!
      expired = described_class.create_for(partner: partner, payload: { c: 3 }, expires_in: -1.second)

      expect(described_class.available).to contain_exactly(fresh)
    end
  end
end
