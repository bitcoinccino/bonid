class AddPartnerToIncidentReports < ActiveRecord::Migration[7.1]
  def change
    add_reference :incident_reports, :partner, foreign_key: true, index: true

    # Optional: backfill from officers if present
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE incident_reports
          SET partner_id = officers.partner_id
          FROM officers
          WHERE incident_reports.officer_id = officers.id
        SQL
      end
    end
  end
end
