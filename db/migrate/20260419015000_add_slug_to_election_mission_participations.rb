# frozen_string_literal: true

# Replaces auto-increment integer ids in URLs with opaque UUIDs so a CEP
# admin (or anyone who landed on a stale URL) cannot enumerate or guess
# /partner_portal/diplomatic_missions/:n/edit by walking sequential ids.
#
# Mission registry ids (HT-CON-MIA, HT-CON-ATL, …) are intentionally
# public — they're like ISO codes for embassies. What must NOT be
# guessable is the per-election participation row id, which is the
# editable surface.
#
# Pattern mirrors AddSlugToPollingCentersAndStations: keep the integer
# primary key for joins/foreign keys, add a `slug` column that
# ActiveRecord exposes via `to_param`, generated server-side.
class AddSlugToElectionMissionParticipations < ActiveRecord::Migration[8.0]
  def up
    add_column :election_mission_participations, :slug, :string

    say_with_time "Backfilling election_mission_participations.slug" do
      ElectionMissionParticipation.reset_column_information
      ElectionMissionParticipation.where(slug: nil).find_each do |p|
        p.update_column(:slug, SecureRandom.uuid)
      end
    end

    change_column_null :election_mission_participations, :slug, false
    add_index :election_mission_participations, :slug, unique: true
  end

  def down
    remove_index  :election_mission_participations, :slug
    remove_column :election_mission_participations, :slug
  end
end
