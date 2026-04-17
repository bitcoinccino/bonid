# frozen_string_literal: true

# Durable record of a seat won in an election. One row per seat per round.
#
# Written by Election::WinnerStampingService at certification. Read by the
# Rezilta page and by downstream press-release / JSON-export pipelines.
class ElectionWinner < ApplicationRecord
  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :election_constituency
  belongs_to :election_candidate
  belongs_to :stamped_by_admin_user, class_name: "AdminUser", optional: true

  validates :seat_label, presence: true
  validates :round,       presence: true, numericality: { only_integer: true }
  validates :vote_count,  presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :total_votes, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :stamped_at,  presence: true

  validates :seat_label,
            uniqueness: { scope: %i[election_id round],
                          message: "gen yon genyan deja pou tou sa a" }

  scope :for_election, ->(election) { where(election_id: election.is_a?(BonvoteElection) ? election.id : election) }
  scope :ordered,      -> { order(:seat_label, :round) }

  def vote_share_pct
    return 0.0 if total_votes.zero?

    (vote_count.to_f / total_votes * 100).round(2)
  end
end
