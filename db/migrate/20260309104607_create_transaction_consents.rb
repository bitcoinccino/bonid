# frozen_string_literal: true

class CreateTransactionConsents < ActiveRecord::Migration[7.1]
  def change
    create_table :transaction_consents do |t|
      t.references :citizen, null: false, foreign_key: { to_table: :users }
      t.references :partner, null: false, foreign_key: true

      t.string  :consent_token,      null: false
      t.string  :transaction_type,   null: false
      t.integer :status,             null: false, default: 0

      t.text    :scopes,             array: true, default: []
      t.decimal :amount,             precision: 12, scale: 2
      t.string  :currency,           default: "HTG"
      t.text    :description
      t.string  :reference_id
      t.string  :callback_url

      t.string  :otp_digest
      t.integer :otp_attempts,       default: 0
      t.datetime :otp_expires_at

      t.string  :notification_channel, default: "email"
      t.datetime :sms_sent_at

      t.datetime :decided_at
      t.string  :signature
      t.string  :ip_address

      t.jsonb   :audit_log,          default: {}
      t.jsonb   :metadata,           default: {}
      t.datetime :expires_at,        null: false

      t.timestamps
    end

    add_index :transaction_consents, :consent_token, unique: true
    add_index :transaction_consents, [:citizen_id, :partner_id, :reference_id],
              unique: true, name: "idx_tx_consent_citizen_partner_ref"
    add_index :transaction_consents, :status
    add_index :transaction_consents, :expires_at
  end
end
