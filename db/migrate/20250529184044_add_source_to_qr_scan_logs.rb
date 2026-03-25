class AddSourceToQrScanLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :qr_scan_logs, :source, :string
  end
end
