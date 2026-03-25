class AddReviewedByAdminIdToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :reviewed_by_admin_id, :integer
  end
end
