# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElectionBallot, type: :model do
  # ── Associations ──────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:election).class_name("BonvoteElection") }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    subject { build(:election_ballot) }

    it { is_expected.to validate_presence_of(:nullifier) }
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_presence_of(:encrypted_choice) }
    it { is_expected.to validate_presence_of(:zkp_commitment) }
    it { is_expected.to validate_presence_of(:ballot_hash) }
    it { is_expected.to validate_presence_of(:receipt_id) }
    it { is_expected.to validate_presence_of(:channel) }
    it { is_expected.to validate_presence_of(:cast_at) }
    it { is_expected.to validate_inclusion_of(:position).in_array(%w[president senator deputy]) }
    it { is_expected.to validate_inclusion_of(:channel).in_array(%w[remote consulate in_person]) }
    it { is_expected.to validate_uniqueness_of(:ballot_hash) }
    it { is_expected.to validate_uniqueness_of(:receipt_id) }

    it "prevents double-voting with same nullifier in same election" do
      election = create(:bonvote_election, :open)
      create(:election_ballot, election: election, nullifier: "same-nullifier")
      dupe = build(:election_ballot, election: election, nullifier: "same-nullifier")
      expect(dupe).not_to be_valid
      expect(dupe.errors[:nullifier]).to include("vote déjà enregistré")
    end

    it "allows same nullifier in different elections" do
      e1 = create(:bonvote_election, :open)
      e2 = create(:bonvote_election, :open)
      create(:election_ballot, election: e1, nullifier: "shared-nullifier")
      ballot = build(:election_ballot, election: e2, nullifier: "shared-nullifier")
      expect(ballot).to be_valid
    end
  end

  # ── Scopes ───────────────────────────────────────────────────
  describe "scopes" do
    let(:election) { create(:bonvote_election, :open) }
    let!(:remote)    { create(:election_ballot, election: election, channel: "remote") }
    let!(:consulate) { create(:election_ballot, :consulate, election: election) }
    let!(:in_person) { create(:election_ballot, :in_person, election: election) }
    let!(:flagged)   { create(:election_ballot, :flagged, election: election) }

    it ".remote returns remote ballots" do
      expect(described_class.remote).to include(remote)
      expect(described_class.remote).not_to include(consulate, in_person)
    end

    it ".consulate returns consulate ballots" do
      expect(described_class.consulate).to include(consulate)
    end

    it ".in_person returns in-person ballots" do
      expect(described_class.in_person).to include(in_person)
    end

    it ".flagged returns location-flagged ballots" do
      expect(described_class.flagged).to include(flagged)
    end

    it ".for_position filters by position" do
      expect(described_class.for_position("president")).to include(remote, consulate, in_person, flagged)
    end
  end

  # ── Verify ───────────────────────────────────────────────────
  describe ".verify" do
    let(:election) { create(:bonvote_election, :open) }
    let!(:ballot)  { create(:election_ballot, election: election) }

    it "returns found: true for a valid ballot hash" do
      result = described_class.verify(ballot.ballot_hash, election.id)
      expect(result[:found]).to be true
      expect(result[:message]).to eq("Vòt ou anrejistre ak siksè.")
      expect(result[:position]).to eq(ballot.position)
    end

    it "returns found: false for unknown hash" do
      result = described_class.verify("nonexistent-hash", election.id)
      expect(result[:found]).to be false
      expect(result[:message]).to eq("Bilten sa a pa jwenn nan rejis la.")
    end

    it "returns found: false for wrong election" do
      other = create(:bonvote_election, :open)
      result = described_class.verify(ballot.ballot_hash, other.id)
      expect(result[:found]).to be false
    end
  end

  # ── Stats ────────────────────────────────────────────────────
  describe ".stats" do
    let(:election) { create(:bonvote_election, :open) }

    before do
      create(:election_ballot, election: election, channel: "remote")
      create(:election_ballot, :consulate, election: election)
      create(:election_ballot, :in_person, election: election)
      create(:election_ballot, :flagged, election: election)
    end

    it "returns comprehensive stats" do
      stats = described_class.stats(election.id)
      expect(stats[:total_votes]).to eq(4)
      # flagged ballot also has channel "remote", so remote_votes = 2
      expect(stats[:remote_votes]).to eq(2)
      expect(stats[:consulate_votes]).to eq(1)
      expect(stats[:in_person_votes]).to eq(1)
      expect(stats[:flagged]).to eq(1)
      expect(stats[:by_channel]).to be_a(Hash)
      expect(stats[:by_position]).to be_a(Hash)
    end
  end
end
