# frozen_string_literal: true

require "rails_helper"

RSpec.describe BonvoteElection, type: :model do
  # ── Associations ──────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to have_many(:election_constituencies).dependent(:destroy) }
    it { is_expected.to have_many(:election_candidates).dependent(:destroy) }
    it { is_expected.to have_many(:election_ballots).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:election_signatures).dependent(:destroy) }
    it { is_expected.to have_many(:electoral_calendars).dependent(:destroy) }
    it { is_expected.to have_many(:voter_eligibility_records).dependent(:destroy) }
    it { is_expected.to belong_to(:parent_election).class_name("BonvoteElection").optional }
    it { is_expected.to have_one(:runoff_election).class_name("BonvoteElection") }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:election_type) }
    it { is_expected.to validate_presence_of(:election_date) }
    it { is_expected.to validate_inclusion_of(:election_type).in_array(%w[general presidential legislative referendum]) }
    it { is_expected.to validate_inclusion_of(:round).in_array([1, 2]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[draft open closed certified cancelled]) }

    it "is valid with factory defaults" do
      election = build(:bonvote_election)
      expect(election).to be_valid
    end
  end

  # ── Scopes ───────────────────────────────────────────────────
  describe "scopes" do
    let!(:draft)     { create(:bonvote_election) }
    let!(:open)      { create(:bonvote_election, :open) }
    let!(:closed)    { create(:bonvote_election, :closed) }
    let!(:certified) { create(:bonvote_election, :certified) }

    it ".active returns draft and open elections" do
      expect(described_class.active).to contain_exactly(draft, open)
    end

    it ".open returns only open elections" do
      expect(described_class.open).to contain_exactly(open)
    end

    it ".round_one returns round 1 elections" do
      expect(described_class.round_one).to include(draft, open, closed, certified)
    end
  end

  # ── Lifecycle ────────────────────────────────────────────────
  describe "lifecycle" do
    let(:election) { create(:bonvote_election) }

    describe "#open!" do
      it "transitions from draft to open" do
        election.open!
        expect(election.reload).to be_open
        expect(election.opened_at).to be_present
      end
    end

    describe "#close!" do
      it "transitions to closed" do
        election.open!
        election.close!
        expect(election.reload).to be_closed
        expect(election.closed_at).to be_present
      end
    end

    describe "#certify!" do
      it "transitions to certified" do
        election.open!
        election.close!
        election.certify!
        expect(election.reload).to be_certified
        expect(election.certified_at).to be_present
      end
    end
  end

  # ── Status Helpers ──────────────────────────────────────────
  describe "status helpers" do
    it "#draft? returns true for draft election" do
      expect(build(:bonvote_election)).to be_draft
    end

    it "#open? returns true for open election" do
      expect(build(:bonvote_election, :open)).to be_open
    end

    it "#closed? returns true for closed election" do
      expect(build(:bonvote_election, :closed)).to be_closed
    end

    it "#certified? returns true for certified election" do
      expect(build(:bonvote_election, :certified)).to be_certified
    end

    it "#runoff? returns true for round 2" do
      expect(build(:bonvote_election, :round_two)).to be_runoff
    end
  end

  # ── Two-Round System ────────────────────────────────────────
  describe "#constituencies_needing_runoff" do
    it "returns constituency IDs where no candidate has >50%" do
      election = create(:bonvote_election, :closed)
      constituency = create(:election_constituency, election: election, department_code: "OU")
      # votes_round1 must be less than half of total ballots to NOT have majority
      create(:election_candidate, :approved, election: election, election_constituency: constituency, votes_round1: 40)
      create(:election_candidate, :approved, election: election, election_constituency: constituency, votes_round1: 35)
      # Total ballot count must be >= sum of candidate votes (75 + buffer)
      100.times do
        create(:election_ballot, election: election, position: "president", department_code: "OU")
      end
      expect(BonvoteElection.find(election.id).constituencies_needing_runoff).to include(constituency.id)
    end

    it "returns empty for draft elections" do
      draft = create(:bonvote_election)
      expect(draft.constituencies_needing_runoff).to eq([])
    end
  end

  describe "#create_runoff!" do
    it "creates a round 2 election with top 2 candidates" do
      election = create(:bonvote_election, :closed, title: "Eleksyon 2026 Round 1")
      constituency = create(:election_constituency, election: election, department_code: "OU")
      create(:election_candidate, :approved, election: election, election_constituency: constituency, votes_round1: 40)
      create(:election_candidate, :approved, election: election, election_constituency: constituency, votes_round1: 35)
      100.times do
        create(:election_ballot, election: election, position: "president", department_code: "OU")
      end

      fresh_election = BonvoteElection.find(election.id)
      runoff = fresh_election.create_runoff!(runoff_date: Date.new(2026, 12, 6))
      expect(runoff).to be_present
      expect(runoff.round).to eq(2)
      expect(runoff.parent_election).to eq(election)
      expect(runoff.status).to eq("draft")
      expect(runoff.election_candidates.count).to eq(2)
    end

    it "raises for non-closed elections" do
      open_election = create(:bonvote_election, :open)
      expect { open_election.create_runoff!(runoff_date: Date.tomorrow) }
        .to raise_error(RuntimeError, /only create runoff from a closed round-1/)
    end
  end

  # ── Stats ───────────────────────────────────────────────────
  describe "stats" do
    let(:election) { create(:bonvote_election, :open) }

    before do
      create(:election_ballot, election: election, channel: "remote")
      create(:election_ballot, election: election, channel: "consulate")
      create(:election_ballot, :in_person, election: election)
    end

    it "#total_votes counts all ballots" do
      expect(election.total_votes).to eq(3)
    end

    it "#votes_by_channel groups by channel" do
      result = election.votes_by_channel
      expect(result["remote"]).to eq(1)
      expect(result["consulate"]).to eq(1)
      expect(result["in_person"]).to eq(1)
    end
  end
end
