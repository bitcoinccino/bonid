class AddStatusToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :status, :integer, default: 0, null: false
    add_index  :visitor_submissions, :status
  end
end
