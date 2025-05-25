class CreateQrScans < ActiveRecord::Migration[8.0]
  def change
    create_table :qr_scans do |t|
      t.references :identity_submission, null: false, foreign_key: true
      t.datetime :scanned_at
      t.string :user_agent
      t.string :ip_address

      t.timestamps
    end
  end
end
