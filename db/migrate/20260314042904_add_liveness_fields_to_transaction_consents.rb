class AddLivenessFieldsToTransactionConsents < ActiveRecord::Migration[8.0]
  def change
    add_column :transaction_consents, :liveness_session_id, :string
    add_column :transaction_consents, :liveness_confidence, :decimal, precision: 5, scale: 2
    add_column :transaction_consents, :biometric_verified_at, :datetime
  end
end
