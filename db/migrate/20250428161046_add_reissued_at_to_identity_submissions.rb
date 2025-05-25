class AddReissuedAtToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :reissued_at, :datetime
  end
end
