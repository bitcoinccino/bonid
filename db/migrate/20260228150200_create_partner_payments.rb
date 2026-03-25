# frozen_string_literal: true

class CreatePartnerPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :partner_payments do |t|
      t.references :partner, null: false, foreign_key: true
      t.references :partner_plan, null: false, foreign_key: true

      # Payment gateway
      t.string :payment_method, null: false, comment: "moncash or stripe"

      # Transaction identifiers
      t.string :order_id, null: false, comment: "Our generated unique order ID"
      t.string :transaction_id, comment: "MonCash transaction ID or Stripe payment intent"
      t.string :payment_token, comment: "MonCash redirect token"

      # Amount & currency
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false, default: "HTG"

      # Status tracking
      t.string :status, null: false, default: "pending", comment: "pending, completed, failed, refunded"
      t.string :payment_type, null: false, default: "subscription", comment: "subscription, addon, overage"

      # Timestamps
      t.datetime :paid_at
      t.datetime :billing_period_start
      t.datetime :billing_period_end

      # Extra data
      t.jsonb :metadata, default: {}
      t.text :failure_reason

      t.timestamps
    end

    add_index :partner_payments, :order_id, unique: true
    add_index :partner_payments, :transaction_id
    add_index :partner_payments, :status
    add_index :partner_payments, :payment_type
    add_index :partner_payments, [:partner_id, :status]
  end
end
