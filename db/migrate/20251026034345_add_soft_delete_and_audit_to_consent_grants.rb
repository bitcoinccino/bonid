# frozen_string_literal: true

class AddSoftDeleteAndAuditToConsentGrants < ActiveRecord::Migration[8.0]
  def change
    # === Soft Delete Support ===
    add_column :consent_grants, :deleted_at, :datetime unless column_exists?(:consent_grants, :deleted_at)
    add_index  :consent_grants, :deleted_at unless index_exists?(:consent_grants, :deleted_at)

    # === Audit Trail Enhancements ===
    add_column :consent_grants, :granted_by_id, :bigint unless column_exists?(:consent_grants, :granted_by_id)
    add_column :consent_grants, :revoked_by_id, :bigint unless column_exists?(:consent_grants, :revoked_by_id)

    # Add foreign key relationships (points to `users` table)
    add_foreign_key :consent_grants, :users, column: :granted_by_id unless foreign_key_exists?(:consent_grants, :users, column: :granted_by_id)
    add_foreign_key :consent_grants, :users, column: :revoked_by_id unless foreign_key_exists?(:consent_grants, :users, column: :revoked_by_id)

    # Reason for status changes or revocations
    add_column :consent_grants, :change_reason, :string unless column_exists?(:consent_grants, :change_reason)

    # JSON-based audit trail for compliance (GDPR, SOC2, etc.)
    add_column :consent_grants, :audit_log, :jsonb, default: {} unless column_exists?(:consent_grants, :audit_log)
  end
end
