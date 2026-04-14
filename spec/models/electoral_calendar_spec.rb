# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElectoralCalendar, type: :model do
  # ── Associations ──────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:bonvote_election) }
  end

  # ── Validations ──────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:phase) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:start_date) }
    it { is_expected.to validate_presence_of(:end_date) }
    it { is_expected.to validate_inclusion_of(:phase).in_array(ElectoralCalendar::PHASES.keys) }

    it "rejects end_date before start_date" do
      cal = build(:electoral_calendar, start_date: Date.current, end_date: Date.current - 1.day)
      expect(cal).not_to be_valid
      expect(cal.errors[:end_date]).to include("dwe apre dat kòmanse")
    end
  end

  # ── Constants ────────────────────────────────────────────────
  describe "constants" do
    it "has 13 CEP phases" do
      expect(ElectoralCalendar::PHASES.size).to eq(13)
    end

    it "includes all critical phases" do
      expect(ElectoralCalendar::PHASES.keys).to include(
        "candidate_registration", "voting_day", "disputes", "second_round_voting"
      )
    end
  end

  # ── Scopes ───────────────────────────────────────────────────
  describe "scopes" do
    let(:election) { create(:bonvote_election) }
    let!(:active_phase)   { create(:electoral_calendar, :active, bonvote_election: election) }
    let!(:past_phase)     { create(:electoral_calendar, :past, bonvote_election: election, phase: "party_registration", name: "Enrejistreman Pati Politik") }
    let!(:upcoming_phase) { create(:electoral_calendar, :upcoming, bonvote_election: election, phase: "campaign", name: "Kanpay Elektoral") }

    it ".active_on returns phases active on a given date" do
      expect(described_class.active_on(Date.current)).to include(active_phase)
      expect(described_class.active_on(Date.current)).not_to include(past_phase, upcoming_phase)
    end

    it ".upcoming returns future phases" do
      expect(described_class.upcoming).to include(upcoming_phase)
      expect(described_class.upcoming).not_to include(past_phase)
    end

    it ".past returns completed phases" do
      expect(described_class.past).to include(past_phase)
      expect(described_class.past).not_to include(upcoming_phase)
    end

    it ".chronological orders by start_date" do
      results = described_class.chronological
      expect(results.first).to eq(past_phase)
    end
  end

  # ── Instance Methods ─────────────────────────────────────────
  describe "instance methods" do
    describe "#active?" do
      it "returns true when current date is within range" do
        cal = build(:electoral_calendar, :active)
        expect(cal).to be_active
      end

      it "returns false for past phases" do
        cal = build(:electoral_calendar, :past)
        expect(cal).not_to be_active
      end
    end

    describe "#duration_days" do
      it "calculates inclusive day count" do
        cal = build(:electoral_calendar, start_date: Date.new(2026, 4, 13), end_date: Date.new(2026, 5, 15))
        expect(cal.duration_days).to eq(33)
      end
    end

    describe "#progress_percentage" do
      it "returns 0 for upcoming phases" do
        cal = build(:electoral_calendar, :upcoming)
        expect(cal.progress_percentage).to eq(0)
      end

      it "returns 100 for past phases" do
        cal = build(:electoral_calendar, :past)
        expect(cal.progress_percentage).to eq(100)
      end

      it "returns partial percentage for active phases" do
        cal = build(:electoral_calendar, :active)
        expect(cal.progress_percentage).to be_between(1, 99)
      end
    end

    describe "#phase_label" do
      it "returns Kreyòl label" do
        cal = build(:electoral_calendar, phase: "voting_day")
        expect(cal.phase_label).to eq("Jounen Vòt")
      end
    end
  end

  # ── Generate Calendar ────────────────────────────────────────
  describe ".generate_for!" do
    let(:election) { create(:bonvote_election) }

    it "creates 13 calendar phases" do
      described_class.generate_for!(election)
      expect(election.electoral_calendars.count).to eq(13)
    end

    it "includes voting day on August 30, 2026" do
      described_class.generate_for!(election)
      voting_day = election.electoral_calendars.find_by(phase: "voting_day")
      expect(voting_day.start_date).to eq(Date.new(2026, 8, 30))
    end

    it "includes second round voting on December 6, 2026" do
      described_class.generate_for!(election)
      r2 = election.electoral_calendars.find_by(phase: "second_round_voting")
      expect(r2.start_date).to eq(Date.new(2026, 12, 6))
    end

    it "is idempotent — clears and regenerates" do
      described_class.generate_for!(election)
      described_class.generate_for!(election)
      expect(election.electoral_calendars.count).to eq(13)
    end
  end

  # ── Current Phase ────────────────────────────────────────────
  describe ".current_phase" do
    let(:election) { create(:bonvote_election) }

    it "returns the currently active phase" do
      active = create(:electoral_calendar, :active, bonvote_election: election)
      expect(described_class.current_phase(election)).to eq(active)
    end

    it "returns nil when no phase is active" do
      create(:electoral_calendar, :past, bonvote_election: election, phase: "party_registration", name: "Enrejistreman Pati Politik")
      expect(described_class.current_phase(election)).to be_nil
    end
  end
end
