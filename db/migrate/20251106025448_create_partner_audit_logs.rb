# db/migrate/20251105220000_create_partner_audit_logs.rb
class CreatePartnerAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :partner_audit_logs do |t|
      t.references :partner, null: false, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.string :event, null: false
      t.text :details
      t.jsonb :metadata, default: {}

      t.timestamps  # ✅ includes created_at and updated_at automatically
    end

    add_index :partner_audit_logs, :created_at
  end
end
