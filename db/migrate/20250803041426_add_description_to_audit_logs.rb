class AddDescriptionToAuditLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :audit_logs, :description, :text
  end
end
