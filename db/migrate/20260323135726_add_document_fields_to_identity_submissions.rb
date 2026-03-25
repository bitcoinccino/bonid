class AddDocumentFieldsToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :document_number, :string
    add_column :identity_submissions, :document_expiry_date, :date
    add_column :identity_submissions, :document_issue_date, :date
    add_index  :identity_submissions, :document_number
  end
end
