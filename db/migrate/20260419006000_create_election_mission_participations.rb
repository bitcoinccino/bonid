# frozen_string_literal: true

# Per-election activation + operating hours for Haiti's diplomatic missions.
#
# The static HaitianDiplomaticMissions concern lists every embassy and
# consulate; this table layers per-election state on top of those static
# IDs: which missions are participating in which BonvoteElection cycle, in
# what status (registration / voting / closed), with what hours, and a
# local contact line for the citizen-facing locator.
#
# `diplomatic_mission_id` is a string FK pointing at the static registry
# (e.g. "HT-CON-MIA"). It is NOT a true bigint FK because the missions are
# code constants, not a table — keeping them in code lets us bump the list
# without a migration, but means we enforce uniqueness + presence here.
class CreateElectionMissionParticipations < ActiveRecord::Migration[8.0]
  def change
    create_table :election_mission_participations do |t|
      t.references :election,
                   null: false,
                   foreign_key: { to_table: :bonvote_elections, on_delete: :cascade }

      t.string  :diplomatic_mission_id, null: false
      t.string  :status,                null: false, default: "inactive"
      t.jsonb   :operating_hours,       null: false, default: {}
      t.string  :contact_phone
      t.string  :contact_email
      t.text    :notes

      t.timestamps
    end

    add_index :election_mission_participations,
              %i[election_id diplomatic_mission_id],
              unique: true,
              name: "idx_emp_election_mission_unique"
    add_index :election_mission_participations, :status
    add_index :election_mission_participations, :operating_hours, using: :gin
  end
end
