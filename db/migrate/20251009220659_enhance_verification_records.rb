class EnhanceVerificationRecords < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    change_table :verification_records, bulk: true do |t|
      t.references :user, null: false, foreign_key: true, index: true unless column_exists?(:verification_records, :user_id)
      t.bigint :verifier_id unless column_exists?(:verification_records, :verifier_id)
      t.string :verifier_type unless column_exists?(:verification_records, :verifier_type)

      t.string :record_type unless column_exists?(:verification_records, :record_type)
      t.string :category unless column_exists?(:verification_records, :category)
      t.string :source unless column_exists?(:verification_records, :source)

      t.integer :access_level, null: false, default: 0 unless column_exists?(:verification_records, :access_level)
      t.string  :visibility unless column_exists?(:verification_records, :visibility)
      t.string  :status, null: false, default: "pending" unless column_exists?(:verification_records, :status)
      t.datetime :verified_at unless column_exists?(:verification_records, :verified_at)

      t.string :verifier_signature, limit: 128 unless column_exists?(:verification_records, :verifier_signature)
      t.text   :notes unless column_exists?(:verification_records, :notes)

      t.jsonb :data, default: {}, null: false unless column_exists?(:verification_records, :data)
      t.jsonb :metadata, default: {} unless column_exists?(:verification_records, :metadata)

      t.timestamps unless column_exists?(:verification_records, :created_at)
    end

    # Safe index additions
    add_index :verification_records, %i[user_id record_type], name: "idx_user_record_type", if_not_exists: true
    add_index :verification_records, %i[user_id status], name: "idx_user_status", if_not_exists: true
    add_index :verification_records, %i[verifier_type verifier_id], name: "idx_verifier", if_not_exists: true
    add_index :verification_records, :access_level, name: "idx_access_level", if_not_exists: true
    add_index :verification_records, :verified_at,  name: "idx_verified_at", if_not_exists: true
    add_index :verification_records, :source,       name: "idx_source", if_not_exists: true

    add_index :verification_records, :data, using: :gin,
              name: "idx_verification_records_data_gin", algorithm: :concurrently, if_not_exists: true
    add_index :verification_records, :metadata, using: :gin,
              name: "idx_verification_records_metadata_gin",
              algorithm: :concurrently, where: "metadata IS NOT NULL", if_not_exists: true
  end
end
