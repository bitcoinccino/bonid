class RemoveAdminUserFkFromPartnerAuditLogs < ActiveRecord::Migration[8.0]
  def change
    remove_foreign_key :partner_audit_logs, :admin_users
  end
end
