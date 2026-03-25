# db/migrate/20250605205200_rename_status_to_report_status_in_incident_reports.rb
class RenameStatusToReportStatusInIncidentReports < ActiveRecord::Migration[7.0]
  def change
    rename_column :incident_reports, :status, :report_status
  end
end