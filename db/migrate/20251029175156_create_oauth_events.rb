class CreateOauthEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :oauth_events do |t|
      t.references :oauth_application, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :event_type, null: false
      t.string :status, default: "pending"
      t.jsonb :payload
      t.text :last_error
      t.timestamps
    end

    add_index :oauth_events, :event_type
    add_index :oauth_events, :status
  end
end
