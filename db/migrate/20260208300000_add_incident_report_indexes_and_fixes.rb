# db/migrate/20260208300000_add_incident_report_indexes_and_fixes.rb
class AddIncidentReportIndexesAndFixes < ActiveRecord::Migration[8.0]
  def change
    # === Performance Indexes ===
    add_index :incident_reports, :crime_type unless index_exists?(:incident_reports, :crime_type)
    add_index :incident_reports, :status unless index_exists?(:incident_reports, :status)
    add_index :incident_reports, :occurred_at unless index_exists?(:incident_reports, :occurred_at)
    add_index :incident_reports, :submitted_at unless index_exists?(:incident_reports, :submitted_at)
    add_index :incident_reports, [:officer_id, :status, :created_at], name: "idx_incidents_officer_status_date"
    add_index :incident_reports, [:partner_id, :status], name: "idx_incidents_partner_status"

    # === Person Involvement Indexes ===
    add_index :person_involvements, :bonid unless index_exists?(:person_involvements, :bonid)
    add_index :person_involvements, :role unless index_exists?(:person_involvements, :role)
    add_index :person_involvements, [:incident_report_id, :role], name: "idx_pi_report_role"

    # === Address Geospatial Index (if using PostGIS) ===
    # add_index :addresses, [:latitude, :longitude], name: "idx_addresses_geo"
  end
end
