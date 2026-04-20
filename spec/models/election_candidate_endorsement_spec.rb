# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElectionCandidateEndorsement, type: :model do
  let(:election)     { create(:bonvote_election) }
  let(:constituency) { create(:election_constituency, election: election) }
  let(:candidate) do
    create(:election_candidate,
           election: election, election_constituency: constituency,
           candidacy_type: "independent")
  end

  describe "associations" do
    it { is_expected.to belong_to(:election_candidate) }
    it { is_expected.to belong_to(:election).class_name("BonvoteElection") }
    it { is_expected.to belong_to(:uploaded_by).class_name("AdminUser").optional }
  end

  describe "validations" do
    it "requires a source" do
      record = described_class.new(election_candidate: candidate, election: election, bonid: "X")
      record.source = nil
      expect(record).not_to be_valid
      expect(record.errors[:source]).to be_present
    end

    it "rejects an unknown source" do
      record = described_class.new(election_candidate: candidate, election: election,
                                   bonid: "X", source: "magic")
      expect(record).not_to be_valid
    end

    it "requires bonid when source is digital" do
      record = described_class.new(election_candidate: candidate, election: election,
                                   source: "digital", cin_number: "ONLY-CIN")
      expect(record).not_to be_valid
      expect(record.errors[:bonid]).to be_present
    end

    it "accepts a csv row with only cin_number (no bonid)" do
      record = described_class.new(election_candidate: candidate, election: election,
                                   source: "csv", cin_number: "CIN-123")
      expect(record).to be_valid
    end

    it "rejects a row with neither bonid nor cin_number" do
      record = described_class.new(election_candidate: candidate, election: election, source: "csv")
      expect(record).not_to be_valid
      expect(record.errors[:base]).to include(a_string_matching(/BonID oswa CIN/))
    end
  end

  describe "callbacks" do
    it "stamps endorsed_at on create when omitted" do
      record = described_class.create!(
        election_candidate: candidate, election: election,
        bonid: "STAMP-TEST", source: "digital"
      )
      expect(record.endorsed_at).to be_present
    end
  end

  describe "scopes" do
    before do
      described_class.create!(election_candidate: candidate, election: election,
                              bonid: "A", source: "digital", voter_roll_verified: true)
      described_class.create!(election_candidate: candidate, election: election,
                              cin_number: "B", source: "csv", voter_roll_verified: false)
    end

    it ".verified returns only voter_roll_verified rows" do
      expect(described_class.verified.count).to eq(1)
    end

    it ".digital returns only source=digital rows" do
      expect(described_class.digital.count).to eq(1)
    end

    it ".csv returns only source=csv rows" do
      expect(described_class.csv.count).to eq(1)
    end
  end

  describe ".verified_count_for" do
    it "counts only verified endorsements for a given candidate" do
      described_class.create!(election_candidate: candidate, election: election,
                              bonid: "V1", source: "digital", voter_roll_verified: true)
      described_class.create!(election_candidate: candidate, election: election,
                              bonid: "V2", source: "digital", voter_roll_verified: false)
      expect(described_class.verified_count_for(candidate)).to eq(1)
    end
  end

  describe "DB uniqueness" do
    it "rejects a duplicate bonid endorsement for the same candidate" do
      described_class.create!(election_candidate: candidate, election: election,
                              bonid: "DUP", source: "digital")
      dup = described_class.new(election_candidate: candidate, election: election,
                                bonid: "DUP", source: "digital", endorsed_at: Time.current)
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same bonid to endorse a different candidate" do
      other = create(:election_candidate, election: election, election_constituency: constituency,
                     candidacy_type: "independent")
      described_class.create!(election_candidate: candidate, election: election,
                              bonid: "SHARED", source: "digital")
      expect do
        described_class.create!(election_candidate: other, election: election,
                                bonid: "SHARED", source: "digital")
      end.not_to raise_error
    end
  end
end
