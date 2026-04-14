# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElectionSignature, type: :model do
  # ── Associations ──────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:election).class_name("BonvoteElection") }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    subject { build(:election_signature) }

    it { is_expected.to validate_presence_of(:bonid) }
    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_presence_of(:signatory_name) }
    it { is_expected.to validate_presence_of(:signed_at) }
    it { is_expected.to validate_inclusion_of(:role).in_array(ElectionSignature::ROLES) }

    it "prevents duplicate roles per election" do
      sig = create(:election_signature, role: "cep_president")
      dupe = build(:election_signature, election: sig.election, role: "cep_president")
      expect(dupe).not_to be_valid
      expect(dupe.errors[:role]).to include("wòl sa a deja siyen")
    end

    it "prevents duplicate BonIDs per election" do
      sig = create(:election_signature)
      dupe = build(:election_signature, election: sig.election, bonid: sig.bonid, role: "cep_secretary")
      expect(dupe).not_to be_valid
      expect(dupe.errors[:bonid]).to include("moun sa a deja siyen")
    end
  end

  # ── Constants ────────────────────────────────────────────────
  describe "constants" do
    it "has 9 CEP member roles" do
      expect(ElectionSignature::ROLES.size).to eq(9)
    end

    it "requires quorum of 5" do
      expect(ElectionSignature::QUORUM).to eq(5)
    end
  end

  # ── Quorum ───────────────────────────────────────────────────
  describe ".quorum_met?" do
    let(:election) { create(:bonvote_election, :closed) }

    it "returns false with fewer than 5 signatures" do
      4.times do |i|
        create(:election_signature, election: election, role: ElectionSignature::ROLES[i])
      end
      expect(described_class.quorum_met?(election.id)).to be false
    end

    it "returns true with 5 or more verified signatures" do
      5.times do |i|
        create(:election_signature, election: election, role: ElectionSignature::ROLES[i], liveness_verified: true)
      end
      expect(described_class.quorum_met?(election.id)).to be true
    end

    it "does not count unverified signatures" do
      5.times do |i|
        create(:election_signature, election: election, role: ElectionSignature::ROLES[i], liveness_verified: false)
      end
      expect(described_class.quorum_met?(election.id)).to be false
    end
  end

  # ── Status ───────────────────────────────────────────────────
  describe ".status_for" do
    let(:election) { create(:bonvote_election, :closed) }

    before do
      3.times do |i|
        create(:election_signature, election: election, role: ElectionSignature::ROLES[i], liveness_verified: true)
      end
    end

    it "returns total count" do
      status = described_class.status_for(election.id)
      expect(status[:total]).to eq(3)
    end

    it "calculates remaining signatures needed" do
      status = described_class.status_for(election.id)
      expect(status[:remaining]).to eq(2)
    end

    it "lists available roles" do
      status = described_class.status_for(election.id)
      expect(status[:available_roles].size).to eq(6)
    end
  end

  # ── Role Labels ─────────────────────────────────────────────
  describe ".role_label" do
    it "returns Kreyòl label for cep_president" do
      expect(described_class.role_label("cep_president")).to eq("Prezidan CEP")
    end

    it "returns Kreyòl label for cep_secretary" do
      expect(described_class.role_label("cep_secretary")).to eq("Sekretè Jeneral CEP")
    end
  end
end
