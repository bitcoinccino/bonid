class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs do |t|
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.bigint :officer_id, null: false
      t.string :badge_id
      t.string :action, null: false
      t.timestamps null: false
    end

    add_index :audit_logs, [:record_type, :record_id]
    add_foreign_key :audit_logs, :officers, column: :officer_id
  end
end
