# frozen_string_literal: true

# Amounts were decimal(12,2), so crypto amounts like 0.002 BTC were
# rounded to 0.00. Widen to 8 decimal places (satoshi precision) and 12
# integer digits. Widening never loses data, so existing rows are safe.
class WidenTransactionConsentAmount < ActiveRecord::Migration[8.0]
  def up
    change_column :transaction_consents, :amount, :decimal, precision: 20, scale: 8
  end

  def down
    change_column :transaction_consents, :amount, :decimal, precision: 12, scale: 2
  end
end
