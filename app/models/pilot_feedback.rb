# frozen_string_literal: true

# Anonymous post-vote feedback from pilot testers.
#
# Collected after the "Vòt ou konte ✓" confirmation screen.
# Links to election_id + receipt_id but contains ZERO voter PII.
#
# The critical metric is `trust_level`:
#   1 = "Wi, m gen konfyans total"
#   2 = "Wi, men m bezwen plis eksplikasyon"
#   3 = "Non, m pa konfyans ankò"
#
# If Phase 2 testers answer 3 at any meaningful rate,
# the team knows exactly what to fix before August 30.
#
class PilotFeedback < ApplicationRecord
  # ── Validations ──
  validates :election_id,  presence: true
  validates :time_to_vote, presence: true, inclusion: { in: [1, 2, 3] }
  validates :photo_clarity, presence: true, inclusion: { in: [1, 2, 3] }
  validates :trust_level,  presence: true, inclusion: { in: [1, 2, 3] }
  validates :receipt_id,   uniqueness: true, allow_blank: true
  validates :comment,      length: { maximum: 1000 }

  # ── Scopes ──
  scope :for_election, ->(eid) { where(election_id: eid) }
  scope :high_trust,   -> { where(trust_level: 1) }
  scope :needs_info,   -> { where(trust_level: 2) }
  scope :no_trust,     -> { where(trust_level: 3) }

  # ── Labels (for admin display) ──
  TIME_LABELS = {
    1 => "Mwens pase 2 minit",
    2 => "2–5 minit",
    3 => "Plis pase 5 minit"
  }.freeze

  PHOTO_LABELS = {
    1 => "Wi, li te klè",
    2 => "Li te OK men ka amelyore",
    3 => "Non, li te difisil"
  }.freeze

  TRUST_LABELS = {
    1 => "Wi, m gen konfyans total",
    2 => "Wi, men m bezwen plis eksplikasyon",
    3 => "Non, m pa konfyans ankò"
  }.freeze

  # ── Aggregate Stats ──
  def self.stats(election_id = nil)
    scope = election_id ? for_election(election_id) : all
    total = scope.count
    return {} if total.zero?

    {
      total: total,
      time_to_vote: {
        fast:   scope.where(time_to_vote: 1).count,
        medium: scope.where(time_to_vote: 2).count,
        slow:   scope.where(time_to_vote: 3).count
      },
      photo_clarity: {
        clear:    scope.where(photo_clarity: 1).count,
        ok:       scope.where(photo_clarity: 2).count,
        difficult: scope.where(photo_clarity: 3).count
      },
      trust_level: {
        full_trust: scope.where(trust_level: 1).count,
        needs_info: scope.where(trust_level: 2).count,
        no_trust:   scope.where(trust_level: 3).count
      },
      trust_score: (scope.where(trust_level: 1).count.to_f / total * 100).round(1),
      comments: scope.where.not(comment: [nil, ""]).count
    }
  end
end
