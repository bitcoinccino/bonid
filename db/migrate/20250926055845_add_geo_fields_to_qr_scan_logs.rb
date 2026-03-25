class AddGeoFieldsToQrScanLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :qr_scan_logs, :country, :string
    add_column :qr_scan_logs, :city, :string
    add_column :qr_scan_logs, :region, :string
    add_column :qr_scan_logs, :organization, :string
  end
end
