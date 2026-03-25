# frozen_string_literal: true

class AddAllowedTransactionTypesToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :allowed_transaction_types, :jsonb, default: [], null: false
    add_index  :partners, :allowed_transaction_types, using: :gin
  end
end
