# frozen_string_literal: true

class CreateOauthAccessTokens < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:oauth_access_tokens)

    create_table :oauth_access_tokens do |t|
      t.references :partner,  null: false, foreign_key: true
      t.references :citizen,  null: false, foreign_key: { to_table: :users }
      t.string     :token,    null: false
      t.string     :scopes,   array: true, default: []
      t.datetime   :expires_at, null: false
      t.datetime   :revoked_at
      t.timestamps
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :expires_at
  end
end
