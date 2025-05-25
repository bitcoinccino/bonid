class AddVerificationFieldsToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :verified_at, :datetime
    add_column :identity_submissions, :expires_at, :datetime
    add_column :identity_submissions, :verification_token, :string
  end
end
