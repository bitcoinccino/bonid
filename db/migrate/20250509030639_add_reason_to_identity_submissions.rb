class AddReasonToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :reason, :string
    add_column :identity_submissions, :other_reason, :string
  end
end
