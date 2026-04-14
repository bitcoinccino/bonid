# frozen_string_literal: true

require "rails_helper"

RSpec.describe Election::AuditService do
  let(:election) { create(:bonvote_election, :open) }

  # ── Voter-Facing: Ballot Verification ────────────────────────
  describe ".verify_ballot_presence" do
    let!(:ballot) { create(:election_ballot, election: election) }

    it "confirms a ballot exists in the ledger" do
      result = described_class.verify_ballot_presence(ballot.ballot_hash, election.id)
      expect(result[:found]).to be true
      expect(result[:message]).to eq("Vòt ou konte")
      expect(result[:timestamp]).to be_present
    end

    it "returns not found for unknown hash" do
      result = described_class.verify_ballot_presence("fake-hash", election.id)
      expect(result[:found]).to be false
      expect(result[:message]).to include("pa jwenn")
    end

    it "returns not found for wrong election" do
      other = create(:bonvote_election, :open)
      result = described_class.verify_ballot_presence(ballot.ballot_hash, other.id)
      expect(result[:found]).to be false
    end
  end

  # ── Tally Proof ──────────────────────────────────────────────
  describe ".generate_tally_proof" do
    context "with ballots" do
      before do
        3.times { create(:election_ballot, election: election) }
        # CommitmentService may not exist yet — define it for test
        unless defined?(CommitmentService)
          stub_const("CommitmentService", Class.new do
            def self.aggregate(commitments)
              OpenSSL::Digest::SHA256.hexdigest(commitments.join)
            end
          end)
        end
      end

      it "generates proof with Merkle root" do
        result = described_class.generate_tally_proof(election.id)
        expect(result[:total_votes]).to eq(3)
        expect(result[:merkle_root]).to be_present
        expect(result[:protocol_version]).to eq("bonid-election-v1")
      end
    end

    context "with no ballots" do
      it "returns zero votes" do
        result = described_class.generate_tally_proof(election.id)
        expect(result[:total_votes]).to eq(0)
        expect(result[:error]).to eq("No ballots found")
      end
    end
  end

  # ── Ledger Integrity ─────────────────────────────────────────
  describe ".verify_ledger_integrity" do
    before do
      3.times { create(:election_ballot, election: election) }
    end

    it "validates a consistent ledger" do
      # First compute the expected root
      ballots = ElectionBallot.where(election_id: election.id).order(:cast_at)
      hashes = ballots.pluck(:ballot_hash)
      expected_root = compute_merkle_root(hashes)

      result = described_class.verify_ledger_integrity(election.id, expected_root)
      expect(result[:valid]).to be true
      expect(result[:total_votes]).to eq(3)
      expect(result[:errors]).to be_empty
    end

    it "detects Merkle root tampering" do
      result = described_class.verify_ledger_integrity(election.id, "tampered-root")
      expect(result[:valid]).to be false
      expect(result[:errors]).to include(match(/Merkle root mismatch/))
    end
  end

  # ── Daily Snapshot ───────────────────────────────────────────
  describe ".daily_snapshot" do
    before do
      create(:election_ballot, election: election, channel: "remote")
      create(:election_ballot, :consulate, election: election)
    end

    it "generates a PII-free snapshot" do
      result = described_class.daily_snapshot(election.id)
      expect(result[:total_votes]).to eq(2)
      expect(result[:votes_by_channel]).to include("remote" => 1, "consulate" => 1)
      expect(result[:merkle_root]).to be_present
      expect(result[:integrity]).to eq("VALID")
    end
  end

  # ── Consulate Tagging ────────────────────────────────────────
  describe ".tag_consulate_vote" do
    it "adds consulate metadata to a ballot" do
      ballot = { ballot_hash: "abc", channel: "remote" }
      result = described_class.tag_consulate_vote(ballot, "HT-CONS-MIAMI", "KIOSK-01")
      expect(result[:channel]).to eq("consulate")
      expect(result[:consulate_id]).to eq("HT-CONS-MIAMI")
      expect(result[:station_id]).to eq("KIOSK-01")
    end
  end

  private

  # Mirror the service's Merkle tree computation for test verification
  def compute_merkle_root(hashes)
    return OpenSSL::Digest::SHA256.hexdigest("empty") if hashes.empty?
    return hashes.first if hashes.size == 1

    hashes << hashes.last if hashes.size.odd?
    parents = hashes.each_slice(2).map do |left, right|
      OpenSSL::Digest::SHA256.hexdigest("#{left}#{right}")
    end
    compute_merkle_root(parents)
  end
end
