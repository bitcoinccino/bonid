class AddMvpFieldsToIncidentReports < ActiveRecord::Migration[8.0]
  def change
    add_column :incident_reports, :report_id, :string
    add_column :incident_reports, :suspect_name, :string
    add_column :incident_reports, :suspect_bonid, :string
    add_column :incident_reports, :suspect_status, :string
    add_column :incident_reports, :officer_name, :string
    add_column :incident_reports, :officer_bonid, :string
    add_column :incident_reports, :officer_unit, :string
    add_column :incident_reports, :submitted_at, :datetime
    add_column :incident_reports, :bonid_case_number, :string
    add_column :incident_reports, :qr_code, :string
    add_index :incident_reports, :report_id, unique: true
    add_index :incident_reports, :suspect_bonid
    add_index :incident_reports, :officer_bonid
    add_index :incident_reports, :bonid_case_number

  end
end
