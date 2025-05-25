class AddRejectionReasonToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :rejection_reason, :text
  end
end
