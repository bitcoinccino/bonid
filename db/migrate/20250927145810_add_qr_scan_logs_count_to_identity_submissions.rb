class AddQrScanLogsCountToIdentitySubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :identity_submissions, :qr_scan_logs_count, :integer, default: 0, null: false
  end
end
