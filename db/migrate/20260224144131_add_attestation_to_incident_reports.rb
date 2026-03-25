class AddAttestationToIncidentReports < ActiveRecord::Migration[8.0]
  def change
    add_column :incident_reports, :signed_by_badge_id, :string
    add_column :incident_reports, :officer_attested_at, :datetime
  end
end
