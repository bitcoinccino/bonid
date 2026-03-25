class AddStatusToIncidentReports < ActiveRecord::Migration[8.0]
  def change
    add_column :incident_reports, :status, :string
  end
end



