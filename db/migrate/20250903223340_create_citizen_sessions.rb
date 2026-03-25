class CreateCitizenSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :citizen_sessions do |t|
      t.references :citizen_profile, null: true, foreign_key: true  # optional link to citizen_profiles
      t.references :user, null: false, foreign_key: true            # always linked to users

      # 🔹 Context & Source Tracking
      t.string  :login_source, null: true   # e.g. "partner:unibank" or "citizen_portal"
      t.string  :ip_address, null: true
      t.string  :user_agent, null: true
      t.string  :device_fingerprint, null: true

      # 🔹 OTP / Session Control
      t.string  :otp_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :citizen_sessions, :login_source
    add_index :citizen_sessions, :device_fingerprint
  end
end
