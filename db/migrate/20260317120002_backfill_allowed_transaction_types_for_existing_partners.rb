# frozen_string_literal: true

class BackfillAllowedTransactionTypesForExistingPartners < ActiveRecord::Migration[8.0]
  def up
    Partner.find_each do |partner|
      next if partner.allowed_transaction_types.present?

      defaults = TransactionConsent.default_types_for_sector(partner.sector)
      partner.update_column(:allowed_transaction_types, defaults)
    end
  end

  def down
    Partner.update_all(allowed_transaction_types: [])
  end
end
