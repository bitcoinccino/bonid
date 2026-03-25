class SetDefaultStatusToDraftOnIncidentReports < ActiveRecord::Migration[7.1]
  def change
    change_column_default :incident_reports, :status, from: nil, to: "draft"
  end
end
