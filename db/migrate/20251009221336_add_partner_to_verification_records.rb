class AddPartnerToVerificationRecords < ActiveRecord::Migration[8.0]
  def change
    # === Add partner reference (optional, for verifying orgs)
    add_reference :verification_records, :partner, foreign_key: true, null: true

    # === Add composite index for faster filtering and analytics
    add_index :verification_records, [ :record_type, :category ],
              name: "idx_verification_type_category"

    # Optional: add combined index for frequent partner lookups
    add_index :verification_records, [ :partner_id, :record_type ],
              name: "idx_partner_record_type"
  end
end
