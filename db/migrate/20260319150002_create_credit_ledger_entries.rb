# frozen_string_literal: true

class CreateCreditLedgerEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_ledger_entries do |t|
      t.references :partner, null: false, foreign_key: true
      t.integer    :amount, null: false                    # positive = top-up, negative = deduction
      t.integer    :balance_after, null: false             # snapshot after this entry
      t.string     :entry_type, null: false                # "top_up", "deduction", "bonus", "refund"
      t.string     :description                            # "QR Scan: Entrance Gate", "+5,000 Credits (MonCash)"
      t.string     :endpoint_key                           # "qr_scan.verify", "identity.show", etc.
      t.string     :payment_method                         # "moncash", "stripe", "admin", nil for deductions
      t.string     :transaction_id                         # MonCash/Stripe transaction ID
      t.string     :bonid                                  # citizen BonID (for deductions)
      t.string     :ip_address
      t.jsonb      :metadata, default: {}
      t.timestamps
    end

    add_index :credit_ledger_entries, [:partner_id, :created_at], name: "idx_ledger_partner_time"
    add_index :credit_ledger_entries, :entry_type
    add_index :credit_ledger_entries, :endpoint_key
  end
end
