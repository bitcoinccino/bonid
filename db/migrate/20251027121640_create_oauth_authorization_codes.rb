class CreateOauthAuthorizationCodes < ActiveRecord::Migration[7.1]
  def change
    create_table :oauth_authorization_codes do |t|
      t.string :code_digest, null: false, index: { unique: true }
      t.datetime :expires_at
      t.datetime :used_at
      t.references :oauth_application, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true  # 👈 change here
      t.text :redirect_uri

      t.timestamps
    end
  end
end
