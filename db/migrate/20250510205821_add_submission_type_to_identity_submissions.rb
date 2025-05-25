class AddSubmissionTypeToIdentitySubmissions < ActiveRecord::Migration[8.0]
   # db/migrate/xxxxxx_add_submission_type_to_identity_submissions.rb
  def change
    add_column :identity_submissions, :submission_type, :string
    add_column :identity_submissions, :submission_type, :string, default: "new"

  end
end
