class CreateApiWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :api_webhook_events do |t|
      t.references :partner, null: false, foreign_key: true
      t.string :event_type
      t.string :bonid
      t.jsonb :payload

      t.timestamps
    end
  end
end
