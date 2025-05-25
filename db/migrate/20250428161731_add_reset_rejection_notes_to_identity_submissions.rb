class AddResetRejectionNotesToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :reset_rejection_notes, :text
  end
end
