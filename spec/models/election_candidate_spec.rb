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

      it "stamps final_listed_at when promoting from preliminary (Article 195)" do
        candidate.submit!
        candidate.publish_to_preliminary!(admin: admin)
        # force close the 48h window
        candidate.update!(preliminary_listed_at: 49.hours.ago)
        candidate.approve!(admin: admin)
        expect(candidate.reload.final_listed_at).to be_present
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

      it "accepts preliminary_listed as a source state (contestation-upheld removal)" do
        candidate.submit!
        candidate.publish_to_preliminary!(admin: admin)
        expect(candidate.registration_status).to eq("preliminary_listed")
        result = candidate.reject!(admin: admin, reason: "Kontestasyon apwouve")
        expect(result).to be_truthy
        expect(candidate.reload.registration_status).to eq("rejected")
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

  # ── Article 192-195: Preliminary List + 48h Contestation Window ───
  describe "preliminary-list workflow" do
    let(:election)     { create(:bonvote_election) }
    let(:constituency) { create(:election_constituency, election: election) }
    let(:admin)        { create(:admin_user) }

    # Party candidate — not subject to the 2% petition gate
    let(:candidate) do
      create(:election_candidate, :party,
             election: election,
             election_constituency: constituency,
             registration_status: "submitted")
    end

    describe "#publish_to_preliminary!" do
      it "transitions submitted → preliminary_listed and opens the contestation window" do
        before_call = Time.current
        candidate.publish_to_preliminary!(admin: admin)
        candidate.reload
        expect(candidate.registration_status).to eq("preliminary_listed")
        expect(candidate.status).to eq("active")
        expect(candidate.preliminary_listed_at).to be_within(2.seconds).of(before_call)
        expect(candidate.approved_by).to eq(admin)
      end

      it "also accepts under_review as a source state" do
        candidate.update!(registration_status: "under_review")
        expect(candidate.publish_to_preliminary!(admin: admin)).to be_truthy
      end

      it "returns false from the wrong state (e.g. draft)" do
        candidate.update!(registration_status: "draft")
        expect(candidate.publish_to_preliminary!(admin: admin)).to be false
      end

      it "refuses independent candidates who have not hit the 2% petition (Article 181.15)" do
        # A populated roll ensures the 2% threshold is non-zero and meaningful.
        create_list(:voter_eligibility_record, 100, bonvote_election: election)
        indie = create(:election_candidate,
                       election: election,
                       election_constituency: constituency,
                       candidacy_type: "independent",
                       registration_status: "submitted")
        expect(indie.publish_to_preliminary!(admin: admin)).to be false
        expect(indie.reload.registration_status).to eq("submitted")
      end
    end

    describe "#contestation_window_open?" do
      it "is true inside the 48-hour window" do
        candidate.update!(registration_status: "preliminary_listed",
                          preliminary_listed_at: 2.hours.ago)
        expect(candidate.contestation_window_open?).to be true
      end

      it "is false once 48 hours have passed" do
        candidate.update!(registration_status: "preliminary_listed",
                          preliminary_listed_at: 49.hours.ago)
        expect(candidate.contestation_window_open?).to be false
      end

      it "is false when not in preliminary_listed state" do
        candidate.update!(preliminary_listed_at: 2.hours.ago)  # still submitted
        expect(candidate.contestation_window_open?).to be false
      end

      it "is false when preliminary_listed_at is nil" do
        candidate.update!(registration_status: "preliminary_listed",
                          preliminary_listed_at: nil)
        expect(candidate.contestation_window_open?).to be false
      end
    end

    describe "#contestation_window_closes_at" do
      it "returns listed_at + 48h" do
        stamp = Time.current
        candidate.update!(preliminary_listed_at: stamp)
        expect(candidate.contestation_window_closes_at).to be_within(1.second).of(stamp + 48.hours)
      end

      it "is nil when never listed" do
        expect(candidate.contestation_window_closes_at).to be_nil
      end
    end
  end

  # ── Article 181.15: 2% Support Petition ───────────────────────
  describe "petition threshold and satisfaction (Article 181.15)" do
    let(:election)     { create(:bonvote_election) }
    let(:constituency) { create(:election_constituency, election: election) }

    describe "#petition_denominator" do
      it "uses the full national roll for president" do
        create_list(:voter_eligibility_record, 3, bonvote_election: election, department_code: "OU")
        create_list(:voter_eligibility_record, 2, bonvote_election: election, department_code: "SE")
        candidate = create(:election_candidate, election: election, election_constituency: constituency, position: "president")
        expect(candidate.petition_denominator).to eq(5)
      end

      it "scopes to the candidate's department for senator" do
        create_list(:voter_eligibility_record, 4, bonvote_election: election, department_code: "OU")
        create_list(:voter_eligibility_record, 3, bonvote_election: election, department_code: "SE")
        candidate = create(:election_candidate, :senator,
                           election: election, election_constituency: constituency,
                           residence_department: "OU")
        expect(candidate.petition_denominator).to eq(4)
      end

      it "scopes to the candidate's commune for deputy" do
        commune_voters = create_list(:voter_eligibility_record, 3, bonvote_election: election)
        commune_voters.each { |v| v.update!(commune_id: 42) }
        create_list(:voter_eligibility_record, 2, bonvote_election: election)  # different commune
        candidate = create(:election_candidate, :deputy,
                           election: election, election_constituency: constituency,
                           commune_id: 42)
        expect(candidate.petition_denominator).to eq(3)
      end
    end

    describe "#petition_threshold" do
      it "rounds 2% up to the next integer" do
        create_list(:voter_eligibility_record, 101, bonvote_election: election)
        candidate = create(:election_candidate, election: election, election_constituency: constituency, position: "president")
        # 2% of 101 = 2.02 → ceil → 3
        expect(candidate.petition_threshold).to eq(3)
      end
    end

    describe "#petition_satisfied?" do
      let(:candidate) do
        create(:election_candidate, election: election, election_constituency: constituency, candidacy_type: "independent")
      end

      it "is always true for non-independent candidates" do
        party = create(:election_candidate, :party, election: election, election_constituency: constituency)
        expect(party.petition_satisfied?).to be true
      end

      it "is false for an independent with no endorsements" do
        create(:voter_eligibility_record, bonvote_election: election)
        expect(candidate.petition_satisfied?).to be false
      end

      it "is true once verified endorsements meet the threshold" do
        # 50 voters → threshold = 1 (ceil(1.0))
        create(:voter_eligibility_record, bonvote_election: election)
        ElectionCandidateEndorsement.create!(
          election_candidate: candidate, election: election,
          bonid: "TEST-BONID-1", source: "digital", voter_roll_verified: true
        )
        expect(candidate.reload.petition_satisfied?).to be true
      end

      it "ignores unverified endorsements" do
        create(:voter_eligibility_record, bonvote_election: election)
        ElectionCandidateEndorsement.create!(
          election_candidate: candidate, election: election,
          cin_number: "CIN-UNMATCHED", source: "csv", voter_roll_verified: false
        )
        expect(candidate.reload.petition_satisfied?).to be false
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

    it "exempts women entirely (Article 185)" do
      candidate = build(:election_candidate, position: "president", sex: "F")
      expect(candidate.calculate_fee).to eq(0)
    end

    it "applies 50% reduction for doctorate holders" do
      candidate = build(:election_candidate, position: "president", sex: "M", education_level: "doctorate")
      expect(candidate.calculate_fee).to eq(400_000)
    end

    it "applies 30% reduction for master's holders" do
      candidate = build(:election_candidate, position: "president", sex: "M", education_level: "masters")
      expect(candidate.calculate_fee).to eq(560_000)
    end

    it "women exemption supersedes degree-based reduction" do
      candidate = build(:election_candidate, position: "senator", sex: "F", education_level: "doctorate")
      expect(candidate.calculate_fee).to eq(0)
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
