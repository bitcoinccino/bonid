class CreateBankProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :bank_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.references :bank, foreign_key: true, index: true

      t.string  :bank_name, null: false
      t.string  :branch_name
      t.string  :account_number, null: false, index: true
      t.string  :account_type
      t.string  :currency, default: "HTG"
      t.string  :wallet_provider
      t.string  :wallet_address
      t.string  :iban
      t.string  :swift_code

      t.boolean :kyc_verified, default: false, null: false
      t.datetime :kyc_verified_at
      t.string   :kyc_reference_id
      t.string   :status, default: "pending"
      t.string   :verification_source
      t.datetime :last_synced_at

      t.jsonb    :metadata, default: {}
      t.string   :created_by_type
      t.bigint   :created_by_id

      t.timestamps
    end

    add_index :bank_profiles, :status
    add_index :bank_profiles, :kyc_verified
    add_index :bank_profiles, :wallet_address
    add_index :bank_profiles, :metadata, using: :gin
  end
end
