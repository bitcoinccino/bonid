# frozen_string_literal: true

# Adds venue_type + expected_capacity to polling_centers so the create
# wizard can capture the building kind (school / church / town hall /
# consulate / etc.) and the partner-admin's planning estimate before any
# Bureau de Vote records exist.
#
# `expected_capacity` is the operator's estimated headcount (used for
# planning how many BVs to register). The existing `total_capacity`
# instance method continues to return the SUM of BV `capacity` values —
# the actual seated capacity once BVs are configured.
class AddVenueTypeAndExpectedCapacityToPollingCenters < ActiveRecord::Migration[8.0]
  def change
    change_table :polling_centers, bulk: true do |t|
      t.string  :venue_type
      t.integer :expected_capacity
      t.index   :venue_type
    end
  end
end
