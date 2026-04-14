# frozen_string_literal: true

# Represents a single election event (e.g. "Eleksyon Jeneral 2026 — Round 1").
#
# Haiti uses absolute-majority two-round voting:
#   - If no candidate gets >50% in round 1, top 2 go to round 2
#   - Applies to president, senators, AND deputies
#
# Lifecycle: draft → open → closed → certified
#   - Round 2 is created from round 1 via `create_runoff!`
#
class BonvoteElection < ApplicationRecord
  self.table_name = "bonvote_elections"

  # ── Associations ──────────────────────────────────────────────
  has_many :election_constituencies,    foreign_key: :election_id, dependent: :destroy
  has_many :election_candidates,       foreign_key: :election_id, dependent: :destroy
  has_many :election_ballots,          foreign_key: :election_id, dependent: :restrict_with_error
  has_many :election_signatures,       foreign_key: :election_id, dependent: :destroy
  has_many :election_bodies,           foreign_key: :election_id, dependent: :destroy
  has_many :election_accreditations,   foreign_key: :election_id, dependent: :destroy
  has_many :election_disputes,         foreign_key: :election_id, dependent: :destroy
  has_many :election_staff_assignments, foreign_key: :election_id, dependent: :destroy
  has_many :electoral_calendars,       dependent: :destroy
  has_many :voter_eligibility_records, dependent: :destroy

  belongs_to :parent_election, class_name: "BonvoteElection", optional: true
  has_one    :runoff_election, class_name: "BonvoteElection", foreign_key: :parent_election_id

  # ── Validations ───────────────────────────────────────────────
  validates :title, presence: true
  validates :election_type, presence: true, inclusion: { in: %w[general presidential legislative referendum simulation] }
  validates :round, presence: true, inclusion: { in: [1, 2] }
  validates :status, presence: true, inclusion: { in: %w[draft open closed certified cancelled] }
  validates :election_date, presence: true

  # ── Scopes ────────────────────────────────────────────────────
  scope :active,    -> { where(status: %w[draft open]) }
  scope :open,      -> { where(status: "open") }
  scope :round_one, -> { where(round: 1) }
  scope :round_two, -> { where(round: 2) }

  # ── Status Helpers ────────────────────────────────────────────
  def open?        = status == "open"
  def closed?      = status == "closed"
  def certified?   = status == "certified"
  def draft?       = status == "draft"
  def runoff?      = round == 2
  def simulation?  = election_type == "simulation"

  def open!
    update!(status: "open", opened_at: Time.current)
  end

  def close!
    update!(status: "closed", closed_at: Time.current)
  end

  def certify!
    update!(status: "certified", certified_at: Time.current)
  end

  # ── Two-Round System ──────────────────────────────────────────

  # Check which constituencies need a runoff (no candidate >50%).
  def constituencies_needing_runoff
    return [] unless round == 1 && status == "closed"

    election_constituencies.map do |constituency|
      candidates = constituency.election_candidates.where(status: "active")
      total_votes = election_ballots.where(position: constituency.position, department_code: constituency.department_code).count

      next nil if total_votes.zero?

      top_candidate = candidates.order(votes_round1: :desc).first
      has_majority = top_candidate && (top_candidate.votes_round1.to_f / total_votes) > 0.5

      has_majority ? nil : constituency.id
    end.compact
  end

  # Create a round-2 election for constituencies that need it.
  def create_runoff!(runoff_date:)
    raise "Can only create runoff from a closed round-1 election" unless round == 1 && closed?

    needs_runoff = constituencies_needing_runoff
    return nil if needs_runoff.empty?

    transaction do
      r2 = BonvoteElection.create!(
        title: title.sub("Round 1", "Round 2").presence || "#{title} — Round 2",
        election_type: election_type,
        round: 2,
        parent_election: self,
        status: "draft",
        election_date: runoff_date,
        cep_public_key: cep_public_key,
        metadata: metadata.merge("parent_election_id" => id)
      )

      election_constituencies.where(id: needs_runoff).each do |c1|
        c2 = c1.dup
        c2.election_id = r2.id
        c2.save!

        top2 = c1.election_candidates
                  .where(status: "active")
                  .order(votes_round1: :desc)
                  .limit(2)

        top2.each do |cand|
          cand.update!(qualified_runoff: true)
          new_cand = cand.dup
          new_cand.election_id = r2.id
          new_cand.election_constituency = c2
          new_cand.votes_round1 = 0
          new_cand.votes_round2 = 0
          new_cand.qualified_runoff = false
          new_cand.winner = false
          new_cand.save!
        end
      end

      r2
    end
  end

  # ── Stats ─────────────────────────────────────────────────────

  def total_votes
    election_ballots.count
  end

  def votes_by_channel
    election_ballots.group(:channel).count
  end

  def votes_by_position
    election_ballots.group(:position).count
  end

  def votes_by_department
    election_ballots.group(:department_code).count
  end
end
