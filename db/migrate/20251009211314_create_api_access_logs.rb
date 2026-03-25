# db/migrate/20251009211314_create_api_access_logs.rb
class CreateApiAccessLogs < ActiveRecord::Migration[8.0]
  def change
    # Avoid re-creating if already exists
    return if table_exists?(:api_access_logs)

    create_table :api_access_logs do |t|
      t.references :partner, null: false, foreign_key: true
      t.references :user, foreign_key: true, null: true
      t.string :endpoint
      t.string :ip_address
      t.boolean :success, default: false
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :api_access_logs, :created_at
    add_index :api_access_logs, :success
  end
end
