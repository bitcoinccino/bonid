class CreateConsentGrants < ActiveRecord::Migration[8.0]
  def change
    create_table :consent_grants do |t|
      t.references :citizen, null: false, foreign_key: { to_table: :users }
      t.references :partner, null: false, foreign_key: true

      # Scopes granted, e.g. ["identity", "bank"]
      t.string  :scopes, array: true, default: []

      # Lifecycle
      t.string  :status, default: "pending"  # pending | granted | revoked | expired
      t.datetime :granted_at
      t.datetime :revoked_at
      t.datetime :expires_at

      # Audit metadata
      t.string :grant_token
      t.jsonb  :metadata, default: {}

      t.timestamps
    end

    add_index :consent_grants, [ :citizen_id, :partner_id ], unique: true
    add_index :consent_grants, :grant_token, unique: true
  end
end
