# frozen_string_literal: true

# Cache geographic scope on the voter record so polling-station lookups
# and transfers don't depend on the voter's current profile:
#
#   - communal_section_id: domestic voters are assigned BVs by section
#     communale (Haiti's finest admin grain, ~570 units). Cached at
#     registration so a later address update doesn't silently move the
#     voter between constituencies.
#
#   - diplomatic_mission_id: diaspora voters are assigned BVs inside
#     polling centers supervised by a specific Haitian consulate/embassy.
#     String key (matches HaitianDiplomaticMissions, e.g. "HT-CON-MIA") —
#     intentionally not a FK because the missions live in a concern,
#     not a table.
class AddSectionAndMissionToVoterRecords < ActiveRecord::Migration[8.0]
  def change
    change_table :voter_eligibility_records do |t|
      t.references :communal_section, foreign_key: true
      t.string :diplomatic_mission_id
    end

    add_index :voter_eligibility_records, :diplomatic_mission_id
  end
end
