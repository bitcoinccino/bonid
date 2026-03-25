class AddReportSignatureToIncidentReports < ActiveRecord::Migration[8.0]
  def change
    add_column :incident_reports, :report_signature, :string
    add_column :incident_reports, :report_signed_at, :datetime
  end
end
