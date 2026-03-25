class RemoveAddressIdFromIncidentReports < ActiveRecord::Migration[7.0]
  def change
    remove_column :incident_reports, :address_id, :bigint
  end
end

