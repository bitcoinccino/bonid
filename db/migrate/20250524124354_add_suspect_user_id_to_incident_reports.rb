class AddSuspectUserIdToIncidentReports < ActiveRecord::Migration[8.0]
  def change
    add_column :incident_reports, :suspect_user_id, :bigint
  end
end
