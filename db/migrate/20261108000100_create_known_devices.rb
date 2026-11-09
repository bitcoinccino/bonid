class CreateKnownDevices < ActiveRecord::Migration[8.0]
  def change
    # Browsers a citizen has signed in from. Identified by a random token kept in
    # a permanent encrypted cookie (only its SHA-256 digest is stored here), so a
    # mobile IP change doesn't count as a "new device".
    create_table :known_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :token_digest, null: false
      t.string   :user_agent
      t.string   :ip_address
      t.string   :city
      t.string   :country
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :known_devices, [ :user_id, :token_digest ], unique: true
  end
end
