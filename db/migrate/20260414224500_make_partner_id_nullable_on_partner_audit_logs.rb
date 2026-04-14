# frozen_string_literal: true

# System-level audit events (reviewer invitations, role changes) have no
# partner context. The model already declares `belongs_to :partner, optional: true`,
# but the column constraint was still NOT NULL. This aligns the schema with the model.
class MakePartnerIdNullableOnPartnerAuditLogs < ActiveRecord::Migration[8.0]
  def change
    change_column_null :partner_audit_logs, :partner_id, true
  end
end
