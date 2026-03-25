class AddPublicTokenToIdentitySubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :identity_submissions, :public_token, :string
    add_index :identity_submissions, :public_token, unique: true
  end
end
