# frozen_string_literal: true

class AddUuidToIncidentReports < ActiveRecord::Migration[8.0]
  def change
    # Add UUID column with PostgreSQL's built-in UUID generation
    # This follows the same pattern used by identity_submissions, verification_records, visitor_submissions
    add_column :incident_reports, :uuid, :uuid, default: -> { "gen_random_uuid()" }, null: false

    # Add unique index for fast lookups
    add_index :incident_reports, :uuid, unique: true
  end
end
