# frozen_string_literal: true

class AddReconciliationFieldsToPartnerPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_payments, :reconciled_at, :datetime
    add_column :partner_payments, :reconciled_by, :string
    add_column :partner_payments, :reconciliation_attempts, :integer, default: 0
    add_column :partner_payments, :last_reconciliation_error, :string
    add_column :partner_payments, :credits, :integer  # how many credits this payment bought
  end
end
