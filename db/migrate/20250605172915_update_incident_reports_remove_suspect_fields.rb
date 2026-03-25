class UpdateIncidentReportsRemoveSuspectFields < ActiveRecord::Migration[8.0]
  def change
    remove_column :incident_reports, :suspect_name, :string
    remove_column :incident_reports, :suspect_bonid, :string
    remove_column :incident_reports, :suspect_status, :string
    remove_column :incident_reports, :suspect_user_id, :bigint
    add_index :incident_reports, :report_id, unique: true unless index_exists?(:incident_reports, :report_id)
  end
end