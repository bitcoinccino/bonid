# frozen_string_literal: true

class CreateDgiPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :dgi_payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :verification_record, null: true, type: :uuid, foreign_key: true

      # Payment details
      t.string  :order_id,       null: false
      t.decimal :amount_htg,     null: false, precision: 15, scale: 2
      t.decimal :fee_htg,        precision: 10, scale: 2, default: 0
      t.decimal :total_htg,      null: false, precision: 15, scale: 2
      t.string  :currency,       null: false, default: "HTG"

      # Method & status
      t.string  :payment_method, null: false  # moncash, natcash, bank_transfer, cash_window
      t.string  :status,         null: false, default: "pending"
      # pending → processing → completed → failed → refunded

      # Provider data
      t.string  :transaction_id                 # MonCash/Natcash transaction ID
      t.string  :payment_token                  # MonCash redirect token
      t.jsonb   :provider_response, default: {} # Full API payload for debugging

      # Form context
      t.string  :form_type                      # nif_registration, patente_declaration, etc.
      t.string  :declaration_number             # The DGI declaration number

      # Timestamps
      t.datetime :paid_at
      t.string   :failure_reason

      t.timestamps
    end

    add_index :dgi_payments, :order_id, unique: true
    add_index :dgi_payments, :transaction_id
    add_index :dgi_payments, [:user_id, :status]
    add_index :dgi_payments, [:verification_record_id, :status]
    add_index :dgi_payments, :form_type
  end
end
