class CreatePartnerApiLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :partner_api_logs do |t|
      t.references :partner, null: false, foreign_key: true
      t.string :endpoint
      t.string :request_method
      t.integer :status_code
      t.integer :status
      t.float :response_time_ms
      t.string :ip_address
      t.text :user_agent
      t.text :request_payload
      t.text :response_body
      t.datetime :requested_at

      t.timestamps
    end
  end
end
