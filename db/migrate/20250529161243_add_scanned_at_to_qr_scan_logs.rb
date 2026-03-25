class AddScannedAtToQrScanLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :qr_scan_logs, :scanned_at, :datetime
  end
end
