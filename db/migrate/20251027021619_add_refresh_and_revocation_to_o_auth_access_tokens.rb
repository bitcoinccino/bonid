# frozen_string_literal: true

class AddRefreshAndRevocationToOAuthAccessTokens < ActiveRecord::Migration[7.1]
  def change
    # ✅ Only add refresh_token if it doesn't exist
    unless column_exists?(:oauth_access_tokens, :refresh_token)
      add_column :oauth_access_tokens, :refresh_token, :string
      add_index  :oauth_access_tokens, :refresh_token, unique: true
    end

    # ✅ Only add revoked_at if not already present
    unless column_exists?(:oauth_access_tokens, :revoked_at)
      add_column :oauth_access_tokens, :revoked_at, :datetime
      add_index  :oauth_access_tokens, :revoked_at
    end
  end
end
