# frozen_string_literal: true

class CreateSettlements < ActiveRecord::Migration[8.0]
  def change
    create_table :settlements do |t|
      # Who we owe
      t.references :partner, null: false, foreign_key: true

      # What payment generated this entry
      t.references :dgi_payment, null: true, foreign_key: true
      t.string :payment_order_id  # DGI-XXXX for quick lookup

      # Money breakdown
      t.decimal :total_collected,   precision: 15, scale: 2, null: false  # what citizen paid
      t.decimal :partner_amount,    precision: 15, scale: 2, null: false  # partner's cut
      t.decimal :bonid_fee,         precision: 15, scale: 2, null: false  # our service fee
      t.string  :currency, default: "HTG", null: false

      # Context
      t.string :form_type           # nif_registration, business_registration, etc.
      t.string :description         # human-readable: "NIF (Formulaire A) — NIF-2026-PAP-0000002"

      # Settlement status
      t.string :status, default: "pending", null: false  # pending, settled, disputed
      t.string :settlement_method                         # bank_wire, zellus_transfer, check, cash
      t.string :settlement_reference                      # wire ref, zellus transaction_id, check #
      t.datetime :settled_at
      t.bigint :settled_by_admin_id                       # who marked it as settled
      t.text :notes

      # Batch grouping (for weekly/monthly settlements)
      t.string :batch_id            # e.g. "BATCH-2026-W13-DGI"
      t.date :period_start
      t.date :period_end

      t.timestamps
    end

    add_index :settlements, :status
    add_index :settlements, :batch_id
    add_index :settlements, [:partner_id, :status], name: "idx_settlements_partner_status"
    add_index :settlements, :payment_order_id
    add_index :settlements, [:period_start, :period_end], name: "idx_settlements_period"
  end
end
