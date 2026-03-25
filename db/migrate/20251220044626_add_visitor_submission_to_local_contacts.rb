class AddVisitorSubmissionToLocalContacts < ActiveRecord::Migration[8.0]
  def change
    add_reference :local_contacts, :visitor_submission, null: true, foreign_key: true
  end
end
