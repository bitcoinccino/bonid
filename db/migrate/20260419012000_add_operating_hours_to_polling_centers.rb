# frozen_string_literal: true

# Adds the JSONB `operating_hours` column to polling_centers so the
# create wizard can capture per-day open/close slots through the same
# HasOperatingHours editor used by ElectoralOffice + ElectionMissionParticipation.
#
# For a Sant Vòt these hours are typically the ELECTION-DAY hours
# (e.g. Saturday 6am-4pm), not regular weekly hours — but the storage
# shape is identical, so display_hours / open_on?(day) just work.
class AddOperatingHoursToPollingCenters < ActiveRecord::Migration[8.0]
  def change
    add_column :polling_centers, :operating_hours, :jsonb, default: {}, null: false
    add_index  :polling_centers, :operating_hours, using: :gin
  end
end
