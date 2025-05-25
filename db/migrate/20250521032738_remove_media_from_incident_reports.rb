class RemoveMediaFromIncidentReports < ActiveRecord::Migration[8.0]
  def change
    remove_column :incident_reports, :media, :jsonb
  end
end
