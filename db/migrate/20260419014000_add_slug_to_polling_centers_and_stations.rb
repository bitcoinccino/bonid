# frozen_string_literal: true

# Replaces auto-increment integer ids in URLs with opaque ULIDs so a
# partner_admin cannot enumerate or guess /polling_centers/:n/edit.
#
# We keep the integer primary key for joins/foreign keys (so all
# existing relationships keep working untouched) and only add a `slug`
# column that ActiveRecord exposes via `to_param`. The slug is
# generated server-side (never accepted from input) and is unique +
# indexed so route lookups stay O(log n).
class AddSlugToPollingCentersAndStations < ActiveRecord::Migration[8.0]
  def up
    add_column :polling_centers,  :slug, :string
    add_column :polling_stations, :slug, :string

    # Backfill before adding the unique index. SecureRandom.uuid is
    # available unconditionally; the format is opaque enough to defeat
    # enumeration without pulling in a new dependency.
    say_with_time "Backfilling polling_centers.slug" do
      PollingCenter.reset_column_information
      PollingCenter.where(slug: nil).find_each do |c|
        c.update_column(:slug, SecureRandom.uuid)
      end
    end

    say_with_time "Backfilling polling_stations.slug" do
      PollingStation.reset_column_information
      PollingStation.where(slug: nil).find_each do |s|
        s.update_column(:slug, SecureRandom.uuid)
      end
    end

    change_column_null :polling_centers,  :slug, false
    change_column_null :polling_stations, :slug, false

    add_index :polling_centers,  :slug, unique: true
    add_index :polling_stations, :slug, unique: true
  end

  def down
    remove_index  :polling_stations, :slug
    remove_index  :polling_centers,  :slug
    remove_column :polling_stations, :slug
    remove_column :polling_centers,  :slug
  end
end
