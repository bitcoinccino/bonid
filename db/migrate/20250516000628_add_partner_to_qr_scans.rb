class AddPartnerToQrScans < ActiveRecord::Migration[8.0]
  def change
    add_reference :qr_scans, :partner, null: false, foreign_key: true
    add_reference :qr_scan_logs, :partner, foreign_key: true
  end
end
