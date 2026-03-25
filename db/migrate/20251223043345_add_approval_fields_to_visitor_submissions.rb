class AddApprovalFieldsToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :approved_at, :datetime
    add_column :visitor_submissions, :approved_by_admin_id, :bigint
  end
end
