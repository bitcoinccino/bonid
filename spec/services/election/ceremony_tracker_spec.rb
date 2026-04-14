# frozen_string_literal: true

require "rails_helper"

RSpec.describe Election::CeremonyTracker do
  let(:election) { create(:bonvote_election, :closed) }

  # ─────────────────────────────────────────────────────────
  # .progress — Quorum Progress Bar
  # ─────────────────────────────────────────────────────────
  describe ".progress" do
    context "with no signatures" do
      it "returns waiting state" do
        prog = described_class.progress(election.id)

        expect(prog[:signed]).to eq(0)
        expect(prog[:required]).to eq(5)
        expect(prog[:total]).to eq(9)
        expect(prog[:quorum_met]).to be false
        expect(prog[:percentage]).to eq(0)
        expect(prog[:status]).to eq("waiting")
        expect(prog[:pending_roles].size).to eq(9)
      end
    end

    context "with 3 of 5 signatures" do
      before do
        sign!(election.id, "cep_president", "Marie Jean-Pierre", 3.minutes.ago)
        sign!(election.id, "cep_vice_president", "Jean Baptiste", 2.minutes.ago)
        sign!(election.id, "cep_secretary", "Rose Augustin", 1.minute.ago)
      end

      it "shows approaching quorum" do
        prog = described_class.progress(election.id)

        expect(prog[:signed]).to eq(3)
        expect(prog[:percentage]).to eq(60)
        expect(prog[:status]).to eq("approaching")
        expect(prog[:quorum_met]).to be false
      end

      it "lists signed and pending roles" do
        prog = described_class.progress(election.id)

        signed_roles = prog[:signatories].map { |s| s[:role] }
        expect(signed_roles).to contain_exactly("cep_president", "cep_vice_president", "cep_secretary")

        pending_roles = prog[:pending_roles].map { |r| r[:role] }
        expect(pending_roles).to include("cep_member_1", "cep_member_2")
        expect(pending_roles.size).to eq(6)
      end

      it "calculates ceremony duration" do
        prog = described_class.progress(election.id)

        expect(prog[:ceremony_duration_seconds]).to be > 0
        expect(prog[:ceremony_started_at]).to be_present
      end

      it "estimates remaining time" do
        prog = described_class.progress(election.id)

        expect(prog[:estimated_remaining_seconds]).to be > 0
      end
    end

    context "with quorum met (5 of 9)" do
      before do
        sign!(election.id, "cep_president", "Marie Jean-Pierre", 5.minutes.ago)
        sign!(election.id, "cep_vice_president", "Jean Baptiste", 4.minutes.ago)
        sign!(election.id, "cep_secretary", "Rose Augustin", 3.minutes.ago)
        sign!(election.id, "cep_member_1", "Pierre Louis", 2.minutes.ago)
        sign!(election.id, "cep_member_2", "Francoise Dorcé", 1.minute.ago)
      end

      it "shows quorum complete" do
        prog = described_class.progress(election.id)

        expect(prog[:signed]).to eq(5)
        expect(prog[:quorum_met]).to be true
        expect(prog[:percentage]).to eq(100)
        expect(prog[:status]).to eq("complete")
      end

      it "has no estimated remaining time" do
        prog = described_class.progress(election.id)

        expect(prog[:estimated_remaining_seconds]).to be_nil
      end
    end
  end

  # ─────────────────────────────────────────────────────────
  # .timeline — Signing Event Log
  # ─────────────────────────────────────────────────────────
  describe ".timeline" do
    before do
      sign!(election.id, "cep_president", "Marie Jean-Pierre", 10.minutes.ago)
      sign!(election.id, "cep_secretary", "Rose Augustin", 7.minutes.ago)
    end

    it "returns ordered signing events" do
      timeline = described_class.timeline(election.id)

      expect(timeline[:events].size).to eq(2)
      expect(timeline[:events].first[:sequence]).to eq(1)
      expect(timeline[:events].first[:role]).to eq("cep_president")
      expect(timeline[:events].last[:sequence]).to eq(2)
      expect(timeline[:events].last[:role]).to eq("cep_secretary")
    end

    it "calculates gap between signatures" do
      timeline = described_class.timeline(election.id)

      # First signature has 0 gap
      expect(timeline[:events].first[:gap_from_previous_seconds]).to eq(0)
      # Second signature has ~3 minute gap
      expect(timeline[:events].last[:gap_from_previous_seconds]).to be > 100
    end

    it "tracks quorum state at each step" do
      timeline = described_class.timeline(election.id)

      expect(timeline[:events].first[:quorum_state]).to eq("1/5")
      expect(timeline[:events].last[:quorum_state]).to eq("2/5")
      expect(timeline[:quorum_met]).to be false
    end
  end

  # ─────────────────────────────────────────────────────────
  # .broadcast_payload — Compact ActionCable payload
  # ─────────────────────────────────────────────────────────
  describe ".broadcast_payload" do
    before do
      sign!(election.id, "cep_president", "Marie Jean-Pierre", 2.minutes.ago)
    end

    it "returns a compact broadcast-ready hash" do
      payload = described_class.broadcast_payload(election.id)

      expect(payload[:type]).to eq("ceremony_progress")
      expect(payload[:signed]).to eq(1)
      expect(payload[:required]).to eq(5)
      expect(payload[:percentage]).to eq(20)
      expect(payload[:quorum_met]).to be false
      expect(payload[:latest_signatory][:role]).to eq("cep_president")
      expect(payload[:pending_count]).to eq(8)
    end
  end

  # ─────────────────────────────────────────────────────────
  # Kreyòl Status Labels
  # ─────────────────────────────────────────────────────────
  describe "status labels" do
    it "shows waiting when no signatures" do
      prog = described_class.progress(election.id)
      expect(prog[:status_label]).to include("tann")
    end

    it "shows approaching when near quorum" do
      4.times { |i| sign!(election.id, Election::MultiSigService::SIGNATORY_ROLES[i], "Signer #{i}", (4 - i).minutes.ago) }

      prog = described_class.progress(election.id)
      expect(prog[:status_label]).to include("Prèske")
    end
  end

  private

  def sign!(election_id, role, name, signed_at)
    ElectionSignature.create!(
      election_id: election_id,
      bonid: "VP-1970-M-OU-#{SecureRandom.hex(3).upcase}",
      role: role,
      signatory_name: name,
      liveness_verified: true,
      signed_at: signed_at,
      key_shard_hash: OpenSSL::Digest::SHA256.hexdigest(SecureRandom.hex(16))
    )
  end
end
