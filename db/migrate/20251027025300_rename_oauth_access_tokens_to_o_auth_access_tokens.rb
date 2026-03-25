# frozen_string_literal: true

class RenameOauthAccessTokensToOAuthAccessTokens < ActiveRecord::Migration[7.1]
  def change
    rename_table :oauth_access_tokens, :o_auth_access_tokens
  end
end
