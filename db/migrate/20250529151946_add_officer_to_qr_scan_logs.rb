class AddOfficerToQrScanLogs < ActiveRecord::Migration[8.0]
  def change
    add_reference :qr_scan_logs, :officer, null: false, foreign_key: true
  end
end
