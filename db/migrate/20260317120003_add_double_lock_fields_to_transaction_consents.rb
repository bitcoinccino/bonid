# frozen_string_literal: true

class AddDoubleLockFieldsToTransactionConsents < ActiveRecord::Migration[8.0]
  def change
    add_column :transaction_consents, :data_access_count, :integer, default: 0, null: false
    add_column :transaction_consents, :data_accessed_at, :datetime
    add_column :transaction_consents, :burn_after_read, :boolean, default: false, null: false
    add_column :transaction_consents, :data_access_window_minutes, :integer

    add_index :transaction_consents, [:consent_token, :partner_id],
              name: "idx_tx_consent_token_partner"
  end
end
