class AddReviewerIdToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :reviewer_id, :integer
  end
end
