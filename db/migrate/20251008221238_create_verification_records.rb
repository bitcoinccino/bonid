# db/migrate/20251008_create_verification_records.rb
class CreateVerificationRecords < ActiveRecord::Migration[8.0]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :verification_records, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :record_type, null: false        # "education" | "employment" | "business" | "property" | ...
      t.string  :category                        # optional sub-type, e.g., "university", "house", "smb"
      t.jsonb   :data, null: false, default: {}  # flexible payload
      t.string  :status, null: false, default: "pending"  # pending | verified | rejected | revoked
      t.integer :access_level, null: false, default: 0      # enum: private/partners/public
      t.datetime :verified_at
      t.uuid    :verifier_id
      t.string  :verifier_type                   # polymorphic (Partner, Officer, Admin)
      t.string  :verifier_signature              # HMAC for integrity
      t.string  :source, null: false, default: "self_reported"
      t.text    :notes
      t.jsonb   :metadata, null: false, default: {}        # audit/device/ip, etc.
      t.timestamps
    end

    add_index :verification_records, :record_type
    add_index :verification_records, :status
    add_index :verification_records, :access_level
    add_index :verification_records, :verifier_id
    add_index :verification_records, :verifier_type
    add_index :verification_records, :created_at
    add_index :verification_records, :data, using: :gin  # JSONB search
  end
end
