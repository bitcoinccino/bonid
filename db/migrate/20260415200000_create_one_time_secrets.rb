# frozen_string_literal: true

class CreateOneTimeSecrets < ActiveRecord::Migration[7.1]
  def change
    create_table :one_time_secrets do |t|
      t.references :partner, null: false, foreign_key: true
      t.string :token, null: false, index: { unique: true }
      t.text :encrypted_payload, null: false
      t.string :label
      t.datetime :expires_at, null: false
      t.datetime :viewed_at
      t.string :viewed_ip
      t.timestamps
    end

    add_index :one_time_secrets, :expires_at
  end
end
