class AddSignatureFieldsToIdentitySubmissions < ActiveRecord::Migration[7.1]
  def change
    change_table :identity_submissions, bulk: true do |t|
      t.jsonb  :signature_metadata, null: false, default: {}
      t.string :signature_hash
      t.datetime :signature_verified_at
      t.bigint :signature_verifier_id
      t.string :signature_verification_method
      t.text   :signature_verification_note
    end

    add_index :identity_submissions, :signature_hash
    add_index :identity_submissions, :signature_verified_at
    add_index :identity_submissions, :signature_verifier_id
  end
end
