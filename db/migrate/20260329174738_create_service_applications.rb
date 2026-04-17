# frozen_string_literal: true

class CreateServiceApplications < ActiveRecord::Migration[8.0]
  def change
    create_table :service_applications do |t|
      t.references :citizen, null: false, foreign_key: { to_table: :users }
      t.references :partner, null: false, foreign_key: true
      t.references :partner_schema, null: false, foreign_key: true

      # Snapshot: the exact schema version this application was started on
      t.integer :schema_version, null: false
      t.jsonb :schema_snapshot, null: false, default: {}  # frozen copy of structure at submission

      # Citizen's submitted data
      t.jsonb :form_data, null: false, default: {}        # { field_key => value }
      t.jsonb :calculated_values, default: {}             # { field_key => computed_value }

      # Signature & seal
      t.boolean :signature_consented, default: false
      t.datetime :signature_applied_at
      t.boolean :sealed, default: false
      t.datetime :sealed_at
      t.string :seal_checksum                             # HMAC for tamper detection

      # Status workflow
      t.string :status, null: false, default: "draft"     # draft, submitted, under_review, approved, rejected, cancelled
      t.text :rejection_reason
      t.references :reviewed_by, foreign_key: { to_table: :users }, null: true
      t.datetime :reviewed_at
      t.datetime :submitted_at

      # PDF
      t.string :pdf_checksum                              # integrity hash of generated PDF
      t.datetime :pdf_generated_at

      # Pricing
      t.integer :total_price_cents, default: 0
      t.string :currency, default: "HTG"
      t.boolean :paid, default: false
      t.datetime :paid_at

      # Verification QR
      t.string :verification_code, null: false            # unique code for QR verification

      t.timestamps
    end

    add_index :service_applications, :status
    add_index :service_applications, :verification_code, unique: true
    add_index :service_applications, [ :citizen_id, :status ]
    add_index :service_applications, [ :partner_id, :status ]
    add_index :service_applications, [ :partner_schema_id, :schema_version ], name: "idx_svc_app_schema_version"
  end
end
