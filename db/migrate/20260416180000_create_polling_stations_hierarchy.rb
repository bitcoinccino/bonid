# frozen_string_literal: true

# Physical voting hierarchy for BonVote elections.
#
#   BonvoteElection
#     └── ElectionConstituency (the political race — already exists)
#     └── PollingCenter  (Sant Vòt — the building: school, library, consulate venue)
#           └── PollingStation  (Biwo Vòt / BV — the table inside that building)
#                 └── VoterEligibilityRecord.polling_station_id
#
# Domestic centers are scoped by commune + communal section (Haiti's finest
# admin grain). Diaspora centers are scoped by `diplomatic_mission_id` — a
# string key from HaitianDiplomaticMissions (e.g. "HT-CON-MIA") so a library
# or school used as a polling venue stays tied to the supervising consulate.
#
# Phase 1: schema + model skeletons only. No behavior change to
# `VoterEligibilityRecord.register_voter!` — that switchover happens in a
# separate commit once seed data exists.
class CreatePollingStationsHierarchy < ActiveRecord::Migration[8.0]
  def change
    # ── 1. PollingCenter — the physical venue ────────────────────────
    create_table :polling_centers do |t|
      t.references :bonvote_election, null: false, foreign_key: { on_delete: :cascade }

      t.string :name,         null: false
      t.string :center_type,  null: false                     # "domestic" | "diaspora"
      t.string :status,       null: false, default: "planned" # planned | open | closed
      t.integer :priority,    null: false, default: 0         # tie-breaker in assignment ordering

      # Physical address (string fields — works for Haitian + foreign addresses)
      t.string :address_line_1
      t.string :address_line_2
      t.string :city
      t.string :state_province
      t.string :postal_code
      t.string :country_code, null: false, default: "HT"
      t.float  :latitude
      t.float  :longitude

      # Domestic geographic scope — nullable because diaspora centers skip these
      t.references :department,       foreign_key: true
      t.references :arrondissement,   foreign_key: true
      t.references :commune,          foreign_key: true
      t.references :communal_section, foreign_key: true

      # Diaspora scope — HaitianDiplomaticMissions string id (e.g. "HT-CON-MIA").
      # Intentionally a string, not a FK: missions are defined in a concern, not a table.
      t.string :diplomatic_mission_id

      t.text :notes

      t.timestamps
    end

    add_index :polling_centers, :center_type
    add_index :polling_centers, :status
    add_index :polling_centers, :diplomatic_mission_id
    add_index :polling_centers,
              [ :bonvote_election_id, :communal_section_id ],
              name: "idx_polling_centers_election_section"
    add_index :polling_centers,
              [ :bonvote_election_id, :diplomatic_mission_id ],
              name: "idx_polling_centers_election_mission"

    # ── 2. PollingStation — the BV (Biwo Vòt) inside a center ────────
    create_table :polling_stations do |t|
      t.references :polling_center, null: false, foreign_key: { on_delete: :cascade }

      t.integer :bv_number,        null: false
      t.integer :capacity,         null: false, default: 450  # Haitian LEEC 2015 standard
      t.integer :registered_count, null: false, default: 0
      t.string  :status,           null: false, default: "open" # open | full | closed
      t.text    :notes

      t.timestamps
    end

    add_index :polling_stations,
              [ :polling_center_id, :bv_number ],
              unique: true,
              name: "idx_polling_stations_center_bv_unique"
    add_index :polling_stations, :status

    # ── 3. Voter linkage + partner audit trail ───────────────────────
    change_table :voter_eligibility_records do |t|
      # Assigned BV (nullable during rollout; mandatory once seed data exists)
      t.references :polling_station, foreign_key: true
      t.datetime   :assigned_at

      # Transfer audit: if CEP moves a voter between BVs
      t.references :transferred_from_station,
                   foreign_key: { to_table: :polling_stations }

      # Registration audit: which CEP office / consulate performed the work.
      # Nullable because passive self-registration has no partner.
      t.references :registered_by_partner,
                   foreign_key: { to_table: :partners }
      t.datetime :registered_at
    end

    # Support "export voter list by BV for printing day-of registers"
    add_index :voter_eligibility_records,
              [ :bonvote_election_id, :polling_station_id ],
              name: "idx_voters_election_station"
  end
end
