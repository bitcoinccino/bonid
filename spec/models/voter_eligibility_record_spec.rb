# frozen_string_literal: true

require "rails_helper"

RSpec.describe VoterEligibilityRecord, type: :model do
  # ── Associations ──────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:bonvote_election) }
    it { is_expected.to belong_to(:user) }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:bonid) }
    it { is_expected.to validate_presence_of(:department_code) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[eligible ineligible suspended]) }
    it { is_expected.to validate_inclusion_of(:channel).in_array(%w[domestic diaspora]) }

    it "prevents duplicate BonID per election" do
      election = create(:bonvote_election)
      user = create(:user)
      create(:voter_eligibility_record,
        bonvote_election: election, user: user,
        bonid: "VP-1970-M-OU-P1234-ABCD", department_code: "OU",
        status: "eligible", constituency_name: "Ouest"
      )
      dupe = build(:voter_eligibility_record,
        bonvote_election: election, user: create(:user),
        bonid: "VP-1970-M-OU-P1234-ABCD", department_code: "OU",
        status: "eligible", constituency_name: "Ouest"
      )
      expect(dupe).not_to be_valid
      expect(dupe.errors[:bonid]).to include("deja anrejistre pou eleksyon sa a")
    end
  end

  # ── Constants ────────────────────────────────────────────────
  describe "constants" do
    it "has 6 ineligibility reasons" do
      expect(VoterEligibilityRecord::INELIGIBILITY_REASONS.size).to eq(6)
    end
  end

  # ── Scopes ───────────────────────────────────────────────────
  describe "scopes" do
    let(:election) { create(:bonvote_election) }
    let!(:eligible_voter) do
      create(:voter_eligibility_record,
        bonvote_election: election, user: create(:user),
        bonid: "VP-1970-M-OU-P1001-AAA1", department_code: "OU",
        status: "eligible", constituency_name: "Ouest", channel: "domestic"
      )
    end
    let!(:ineligible_voter) do
      create(:voter_eligibility_record,
        bonvote_election: election, user: create(:user),
        bonid: "VP-1970-M-OU-P1002-BBB2", department_code: "OU",
        status: "ineligible", ineligibility_reason: "underage"
      )
    end

    it ".eligible returns eligible records" do
      expect(described_class.eligible).to include(eligible_voter)
      expect(described_class.eligible).not_to include(ineligible_voter)
    end

    it ".ineligible returns ineligible records" do
      expect(described_class.ineligible).to include(ineligible_voter)
    end

    it ".domestic filters domestic voters" do
      expect(described_class.domestic).to include(eligible_voter)
    end
  end

  # ── Instance Methods ─────────────────────────────────────────
  describe "#eligible?" do
    it "returns true for eligible status" do
      record = build(:voter_eligibility_record, status: "eligible")
      expect(record).to be_eligible
    end

    it "returns false for ineligible status" do
      record = build(:voter_eligibility_record, status: "ineligible")
      expect(record).not_to be_eligible
    end
  end

  describe "#mark_voted!" do
    it "sets has_voted and voted_at" do
      election = create(:bonvote_election)
      record = create(:voter_eligibility_record,
        bonvote_election: election, user: create(:user),
        bonid: "VP-1970-M-OU-P1001-AAA1", department_code: "OU",
        status: "eligible", constituency_name: "Ouest"
      )
      record.mark_voted!
      expect(record.has_voted).to be true
      expect(record.voted_at).to be_present
    end
  end

  describe "#ineligibility_label" do
    it "returns Kreyòl label" do
      record = build(:voter_eligibility_record, ineligibility_reason: "underage")
      expect(record.ineligibility_label).to eq("Mwens ke 18 an")
    end
  end

  # ── Stats ────────────────────────────────────────────────────
  describe ".stats_for" do
    let(:election) { create(:bonvote_election) }

    before do
      3.times do |i|
        create(:voter_eligibility_record,
          bonvote_election: election, user: create(:user),
          bonid: "VP-1970-M-OU-P100#{i}-AAA#{i}", department_code: "OU",
          status: "eligible", constituency_name: "Ouest", channel: "domestic"
        )
      end
      create(:voter_eligibility_record,
        bonvote_election: election, user: create(:user),
        bonid: "VP-1970-M-OU-P1010-BBB0", department_code: "OU",
        status: "ineligible", ineligibility_reason: "underage", channel: nil
      )
    end

    it "returns voter stats" do
      stats = described_class.stats_for(election)
      expect(stats[:total_registered]).to eq(4)
      expect(stats[:eligible]).to eq(3)
      expect(stats[:ineligible]).to eq(1)
      expect(stats[:domestic]).to eq(3)
    end
  end
end
