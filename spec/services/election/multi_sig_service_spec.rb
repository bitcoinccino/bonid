# frozen_string_literal: true

require "rails_helper"

RSpec.describe Election::MultiSigService do
  let(:election) { create(:bonvote_election, :closed) }

  def build_signatory(role:, bonid: nil)
    {
      bonid: bonid || "VP-1960-M-OU-P#{SecureRandom.hex(2).upcase}-#{SecureRandom.hex(1).upcase}",
      role: role,
      name: "Manm #{role}",
      liveness_session_id: SecureRandom.uuid,
      liveness_verified: true,
      key_shard: SecureRandom.hex(32)
    }
  end

  # ── Add Signature ────────────────────────────────────────────
  describe ".add_signature" do
    it "records a valid signature" do
      result = described_class.add_signature(election.id, build_signatory(role: "cep_president"))
      expect(result[:signatures_count]).to eq(1)
      expect(result[:quorum_met]).to be false
      expect(result[:remaining]).to eq(4)
    end

    it "raises for duplicate BonID" do
      sig = build_signatory(role: "cep_president", bonid: "VP-1960-M-OU-P1234-ABCD")
      described_class.add_signature(election.id, sig)

      dupe = build_signatory(role: "cep_vice_president", bonid: "VP-1960-M-OU-P1234-ABCD")
      expect { described_class.add_signature(election.id, dupe) }
        .to raise_error(Election::MultiSigService::DuplicateSignatureError)
    end

    it "raises for invalid role" do
      sig = build_signatory(role: "cep_president")
      sig[:role] = "random_person"
      expect { described_class.add_signature(election.id, sig) }
        .to raise_error(Election::MultiSigService::InvalidSignatoryError)
    end

    it "raises without BonID" do
      sig = build_signatory(role: "cep_president")
      sig[:bonid] = ""
      expect { described_class.add_signature(election.id, sig) }
        .to raise_error(Election::MultiSigService::InvalidSignatoryError, /BonID obligatwa/)
    end

    it "raises without liveness verification" do
      sig = build_signatory(role: "cep_president")
      sig[:liveness_verified] = false
      expect { described_class.add_signature(election.id, sig) }
        .to raise_error(Election::MultiSigService::InvalidSignatoryError, /byometrik/)
    end

    it "raises without key shard" do
      sig = build_signatory(role: "cep_president")
      sig[:key_shard] = ""
      expect { described_class.add_signature(election.id, sig) }
        .to raise_error(Election::MultiSigService::InvalidSignatoryError, /shard/)
    end
  end

  # ── Quorum ───────────────────────────────────────────────────
  describe "quorum" do
    it "reaches quorum at 5 signatures" do
      roles = Election::MultiSigService::SIGNATORY_ROLES.first(5)
      result = nil
      roles.each do |role|
        result = described_class.add_signature(election.id, build_signatory(role: role))
      end
      expect(result[:quorum_met]).to be true
      expect(result[:remaining]).to eq(0)
    end

    it "does not reach quorum at 4 signatures" do
      roles = Election::MultiSigService::SIGNATORY_ROLES.first(4)
      result = nil
      roles.each do |role|
        result = described_class.add_signature(election.id, build_signatory(role: role))
      end
      expect(result[:quorum_met]).to be false
      expect(result[:remaining]).to eq(1)
    end
  end

  # ── Status ───────────────────────────────────────────────────
  describe ".status" do
    it "returns full status with available roles" do
      described_class.add_signature(election.id, build_signatory(role: "cep_president"))
      described_class.add_signature(election.id, build_signatory(role: "cep_secretary"))

      status = described_class.status(election.id)
      expect(status[:total]).to eq(2)
      expect(status[:required]).to eq(5)
      expect(status[:met]).to be false
      expect(status[:remaining]).to eq(3)
      expect(status[:available_roles]).not_to include("cep_president", "cep_secretary")
      expect(status[:available_roles].size).to eq(7)
    end
  end

  # ── Role Labels ──────────────────────────────────────────────
  describe ".role_label" do
    it "returns Kreyòl labels" do
      expect(described_class.role_label("cep_president")).to eq("Prezidan CEP")
      expect(described_class.role_label("cep_vice_president")).to eq("Vis-Prezidan CEP")
      expect(described_class.role_label("cep_member_3")).to eq("Manm Konseye 3")
    end
  end

  # ── Constants ────────────────────────────────────────────────
  describe "constants" do
    it "requires 5-of-9 quorum" do
      expect(described_class::QUORUM_REQUIRED).to eq(5)
      expect(described_class::TOTAL_SIGNATORIES).to eq(9)
      expect(described_class::SIGNATORY_ROLES.size).to eq(9)
    end
  end
end
