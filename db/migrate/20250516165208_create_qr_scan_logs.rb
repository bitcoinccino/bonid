class CreateQrScanLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :qr_scan_logs do |t|
      t.references :qr_scan, null: false, foreign_key: true
      t.references :partner, foreign_key: true
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
  end
end
