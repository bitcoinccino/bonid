class AddResetRequestToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :reset_requested, :boolean
    add_column :identity_submissions, :reset_requested_at, :datetime
  end
end
