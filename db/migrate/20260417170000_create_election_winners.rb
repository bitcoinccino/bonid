# frozen_string_literal: true

# Durable winners table — one row per seat awarded in an election.
#
# Why a dedicated table vs. the existing `election_candidates.winner` flag:
#
#   - The flag is mutable; a bug or admin mistake could flip it after
#     certification. Winners are a historical fact and belong in an
#     append-mostly ledger with a stamp timestamp.
#   - Multi-seat races (senators — 2 or 3 seats per department) need one
#     winner row per seat, which a single boolean can't express.
#   - The Rezilta page can render instantly from this table without
#     recomputing vote tallies on every view.
#
# The flag on ElectionCandidate is still updated for backward compatibility
# with existing scopes + partner integrations.
#
# Seat label conventions:
#   president                    -> "president"
#   senator, department "OUEST"  -> "senator_ouest_seat_1", "senator_ouest_seat_2"
#   deputy, commune 42           -> "deputy_commune_42"
#   dyaspora president           -> "president" (same as domestic)
class CreateElectionWinners < ActiveRecord::Migration[8.0]
  def change
    create_table :election_winners do |t|
      t.references :election, null: false,
                   foreign_key: { to_table: :bonvote_elections }
      t.references :election_constituency, null: false, foreign_key: true
      t.references :election_candidate,    null: false, foreign_key: true

      t.string  :seat_label,   null: false      # e.g. "senator_ouest_seat_1"
      t.integer :round,        null: false, default: 1
      t.integer :vote_count,   null: false, default: 0
      t.decimal :vote_share,   precision: 6, scale: 4  # 0.0000–1.0000
      t.integer :total_votes,  null: false, default: 0

      t.datetime :stamped_at,  null: false
      # AdminUser.id that triggered the certification; nil for system-run.
      t.references :stamped_by_admin_user,
                   foreign_key: { to_table: :admin_users }

      t.timestamps
    end

    # One seat can only be held by one winner per election per round.
    add_index :election_winners,
              [:election_id, :seat_label, :round],
              unique: true,
              name: "idx_election_winners_seat_unique"
  end
end
