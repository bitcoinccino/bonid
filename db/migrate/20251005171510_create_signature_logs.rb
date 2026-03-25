class CreateSignatureLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :signature_logs do |t|
      t.references :identity_submission, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.bigint :verifier_id, index: true

      t.string :action, null: false
      t.string :signature_hash
      t.jsonb :metadata, null: false, default: {}
      t.boolean :verified, default: false
      t.datetime :verified_at
      t.text :note

      t.timestamps
    end

    add_index :signature_logs, :signature_hash
    add_index :signature_logs, :action
  end
end
