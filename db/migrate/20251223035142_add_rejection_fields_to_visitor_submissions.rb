class AddRejectionFieldsToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :rejection_reason, :string
    add_column :visitor_submissions, :rejection_notes, :text
    add_column :visitor_submissions, :rejected_at, :datetime
    add_column :visitor_submissions, :rejected_by_admin_id, :bigint
  end
end
