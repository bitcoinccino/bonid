# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElectionCandidate, type: :model do
  # ── Associations ──────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:election).class_name("BonvoteElection") }
    it { is_expected.to belong_to(:election_constituency) }
    it { is_expected.to belong_to(:party_registration).class_name("ElectionPartyRegistration").optional }
    it { is_expected.to belong_to(:user).optional }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:full_name) }
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_inclusion_of(:position).in_array(%w[president senator deputy]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active withdrawn disqualified]) }
    it { is_expected.to validate_inclusion_of(:candidacy_type).in_array(%w[party grouping independent]) }

    it "is valid with factory defaults" do
      candidate = build(:election_candidate)
      expect(candidate).to be_valid
    end
  end

  # ── Registration Workflow ────────────────────────────────────
  describe "registration workflow" do
    let(:election)      { create(:bonvote_election) }
    let(:constituency)  { create(:election_constituency, election: election) }
    let(:candidate)     { create(:election_candidate, election: election, election_constituency: constituency, registration_status: nil) }

    describe "#submit!" do
      it "transitions from draft/nil to submitted" do
        candidate.submit!
        expect(candidate.reload.registration_status).to eq("submitted")
        expect(candidate.submitted_at).to be_present
        expect(candidate.recepisse_number).to be_present
        expect(candidate.registration_fee_gourdes).to be_present
      end

      it "generates a unique recepisse number" do
        candidate.submit!
        expect(candidate.recepisse_number).to match(/\AREC-\d{4}-P-[A-F0-9]{8}\z/)
      end

      it "returns false if already submitted" do
        candidate.submit!
        expect(candidate.submit!).to be false
      end
    end

    describe "#start_review!" do
      it "transitions from submitted to under_review" do
        candidate.submit!
        candidate.start_review!
        expect(candidate.reload.registration_status).to eq("under_review")
      end
    end

    describe "#approve!" do
      let(:admin) { create(:admin_user) }

      it "transitions to approved and active" do
        candidate.submit!
        candidate.approve!(admin: admin)
        candidate.reload
        expect(candidate.registration_status).to eq("approved")
        expect(candidate.status).to eq("active")
        expect(candidate.approved_at).to be_present
        expect(candidate.approved_by).to eq(admin)
      end
    end

    describe "#reject!" do
      let(:admin) { create(:admin_user) }

      it "transitions to rejected and disqualified" do
        candidate.submit!
        candidate.reject!(admin: admin, reason: "Dokiman pa konplè")
        candidate.reload
        expect(candidate.registration_status).to eq("rejected")
        expect(candidate.status).to eq("disqualified")
        expect(candidate.rejection_reason).to eq("Dokiman pa konplè")
      end
    end

    describe "#withdraw!" do
      it "transitions to withdrawn" do
        candidate.withdraw!
        expect(candidate.reload.registration_status).to eq("withdrawn")
        expect(candidate.status).to eq("withdrawn")
      end
    end
  end

  # ── Fee Calculation ──────────────────────────────────────────
  describe "#calculate_fee" do
    it "returns 800,000 G for president" do
      candidate = build(:election_candidate, position: "president")
      expect(candidate.calculate_fee).to eq(800_000)
    end

    it "returns 120,000 G for senator" do
      candidate = build(:election_candidate, :senator)
      expect(candidate.calculate_fee).to eq(120_000)
    end

    it "returns 60,000 G for deputy" do
      candidate = build(:election_candidate, :deputy)
      expect(candidate.calculate_fee).to eq(60_000)
    end

    it "applies 50% reduction for eligible candidates" do
      candidate = build(:election_candidate, position: "president", fee_reduced: true)
      expect(candidate.calculate_fee).to eq(400_000)
    end
  end

  # ── Document Checklist ──────────────────────────────────────
  describe "document checklist" do
    it "returns more documents for presidential candidates" do
      pres = build(:election_candidate, position: "president")
      dep = build(:election_candidate, :deputy)
      expect(pres.required_documents.size).to be >= dep.required_documents.size
    end

    it "includes party mandate for party candidates" do
      party = build(:election_candidate, :party)
      fields = party.required_documents.map { |d| d[:field] }
      expect(fields).to include(:doc_party_mandate)
      expect(fields).not_to include(:doc_support_petition)
    end

    it "includes support petition for independent candidates" do
      indie = build(:election_candidate, candidacy_type: "independent")
      fields = indie.required_documents.map { |d| d[:field] }
      expect(fields).to include(:doc_support_petition)
      expect(fields).not_to include(:doc_party_mandate)
    end
  end

  # ── Scopes ───────────────────────────────────────────────────
  describe "scopes" do
    let(:election)     { create(:bonvote_election) }
    let(:constituency) { create(:election_constituency, election: election) }

    it ".approved returns only approved candidates" do
      approved = create(:election_candidate, :approved, election: election, election_constituency: constituency)
      rejected = create(:election_candidate, :rejected, election: election, election_constituency: constituency)
      expect(described_class.approved).to include(approved)
      expect(described_class.approved).not_to include(rejected)
    end

    it ".presidents filters by president position" do
      pres = create(:election_candidate, election: election, election_constituency: constituency, position: "president")
      expect(described_class.presidents).to include(pres)
    end
  end

  # ── Display Helpers ─────────────────────────────────────────
  describe "#display_name" do
    it "includes party acronym when present" do
      candidate = build(:election_candidate, :party, full_name: "Jean Dupont")
      expect(candidate.display_name).to include("PHTK")
    end

    it "returns full name for independent candidates" do
      candidate = build(:election_candidate, full_name: "Marie Duval")
      expect(candidate.display_name).to eq("Marie Duval")
    end
  end

  # ── Stats ───────────────────────────────────────────────────
  describe ".registration_stats_for" do
    let(:election)     { create(:bonvote_election) }
    let(:constituency) { create(:election_constituency, election: election) }

    before do
      create(:election_candidate, election: election, election_constituency: constituency, registration_status: "submitted")
      create(:election_candidate, :approved, election: election, election_constituency: constituency)
      create(:election_candidate, :rejected, election: election, election_constituency: constituency)
    end

    it "returns grouped stats" do
      stats = described_class.registration_stats_for(election)
      expect(stats[:total]).to eq(3)
      expect(stats[:submitted]).to eq(1)
      expect(stats[:approved]).to eq(1)
      expect(stats[:rejected]).to eq(1)
    end
  end
end
