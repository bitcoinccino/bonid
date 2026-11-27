# Per-item read state for the citizen notification bell: a row means the
# citizen opened that notification. Keys look like "scan:12",
# "consent:3:1731900000", "txn:7", "app:5:approved"
# (CitizenActivityEvent#notification_key).
class CreateNotificationReads < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_reads do |t|
      t.references :user, null: false, foreign_key: true
      t.string :key, null: false, limit: 100
      t.timestamps
    end
    add_index :notification_reads, [ :user_id, :key ], unique: true
  end
end
