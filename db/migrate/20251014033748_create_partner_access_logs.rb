# db/migrate/20251014xxxxxx_create_partner_access_logs.rb
class CreatePartnerAccessLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :partner_access_logs do |t|
      t.references :partner, null: false, foreign_key: true
      t.references :admin_user, null: true, foreign_key: true
      t.string :action, null: false
      t.string :reason
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :partner_access_logs, :action
    add_index :partner_access_logs, :created_at
  end
end
