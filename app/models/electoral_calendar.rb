# frozen_string_literal: true

class ElectoralCalendar < ApplicationRecord
  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :bonvote_election

  # ============================================================
  # PHASES — maps to CEP's 8-segment electoral cycle
  # ============================================================
  PHASES = {
    "party_registration"     => "Enrejistreman Pati Politik",
    "candidate_registration" => "Depo Kandida",
    "voter_registration"     => "Enrejistreman Elektè",
    "campaign"               => "Kanpay Elektoral",
    "silence_period"         => "Peryòd Silans",
    "voting_day"             => "Jounen Vòt",
    "tabulation"             => "Tabulasyon Rezilta",
    "preliminary_results"    => "Rezilta Preliminè",
    "disputes"               => "Kontestasyon",
    "final_results"          => "Rezilta Definitif",
    "second_round_campaign"  => "Kanpay Dezyèm Tou",
    "second_round_voting"    => "Jou Vòt Dezyèm Tou",
    "second_round_results"   => "Rezilta Definitif Dezyèm Tou"
  }.freeze

  RESPONSIBLE_BODIES = %w[cep bed bec bcev oni].freeze

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :phase, presence: true, inclusion: { in: PHASES.keys }
  validates :name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date

  # ============================================================
  # SCOPES
  # ============================================================
  scope :public_visible, -> { where(public_visible: true) }
  scope :chronological,  -> { order(:start_date) }
  scope :active_on, ->(date = Date.current) { where("start_date <= ? AND end_date >= ?", date, date) }
  scope :upcoming,  -> { where("start_date > ?", Date.current).order(:start_date) }
  scope :past,      -> { where("end_date < ?", Date.current).order(end_date: :desc) }
  scope :for_phase, ->(phase) { where(phase: phase) }

  # ============================================================
  # CLASS METHODS
  # ============================================================

  # Current phase for an election (or globally)
  def self.current_phase(election = nil)
    scope = active_on
    scope = scope.where(bonvote_election: election) if election
    scope.order(:start_date).first
  end

  # All phases for timeline display
  def self.timeline_for(election)
    where(bonvote_election: election).chronological
  end

  # ============================================================
  # INSTANCE METHODS
  # ============================================================
  def active?
    Date.current.between?(start_date, end_date)
  end

  def upcoming?
    start_date > Date.current
  end

  def past?
    end_date < Date.current
  end

  def duration_days
    (end_date - start_date).to_i + 1
  end

  def progress_percentage
    return 0 if upcoming?
    return 100 if past?

    elapsed = (Date.current - start_date).to_i
    total = (end_date - start_date).to_i
    return 100 if total.zero?

    [(elapsed.to_f / total * 100).round, 100].min
  end

  def phase_label
    PHASES[phase] || phase.titleize
  end

  def responsible_body_label
    return nil if responsible_body.blank?
    responsible_body.upcase
  end

  # Generate the official 2026 CEP calendar for an election.
  # Idempotent: clears existing phases before re-generating.
  def self.generate_for!(election)
    where(bonvote_election_id: election.id).destroy_all

    phases = [
      { phase: "party_registration",     name: "Enrejistreman Pati Politik",            start: "2026-03-02", end: "2026-03-12" },
      { phase: "candidate_registration", name: "Depo Kandida",                          start: "2026-04-13", end: "2026-05-15" },
      { phase: "voter_registration",     name: "Enrejistreman Elektè (Lis Elektoral)",  start: "2026-04-01", end: "2026-06-29" },
      { phase: "campaign",               name: "Kanpay Elektoral (1ye tou)",            start: "2026-05-19", end: "2026-08-28" },
      { phase: "silence_period",         name: "Peryòd Silans",                         start: "2026-08-29", end: "2026-08-30" },
      { phase: "voting_day",             name: "Jou Vòt (1ye tou)",                     start: "2026-08-30", end: "2026-08-30" },
      { phase: "tabulation",             name: "Tabulasyon Rezilta",                    start: "2026-08-30", end: "2026-09-01" },
      { phase: "preliminary_results",    name: "Rezilta Preliminè",                     start: "2026-09-02", end: "2026-09-08" },
      { phase: "disputes",               name: "Kontestasyon",                          start: "2026-09-03", end: "2026-10-02" },
      { phase: "final_results",          name: "Rezilta Definitif (1ye tou)",           start: "2026-10-03", end: "2026-10-03" },
      { phase: "second_round_campaign",  name: "Kanpay Dezyèm Tou",                    start: "2026-11-06", end: "2026-12-05" },
      { phase: "second_round_voting",    name: "Jou Vòt Dezyèm Tou",                   start: "2026-12-06", end: "2026-12-06" },
      { phase: "second_round_results",   name: "Rezilta Definitif Dezyèm Tou",         start: "2027-01-07", end: "2027-01-07" }
    ]

    phases.each do |p|
      create!(
        bonvote_election: election,
        phase: p[:phase],
        name: p[:name],
        start_date: p[:start],
        end_date: p[:end],
        description: "Faz ofisyèl CEP 2026 (daprè kalandriye ofisyèl)",
        public_visible: true,
        responsible_body: "cep"
      )
    end
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?
    errors.add(:end_date, "dwe apre dat kòmanse") if end_date < start_date
  end
end
