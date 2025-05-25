class AddResetRequestStatusToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :reset_request_status, :string
    add_column :identity_submissions, :reset_rejection_reason, :text
  end
end
