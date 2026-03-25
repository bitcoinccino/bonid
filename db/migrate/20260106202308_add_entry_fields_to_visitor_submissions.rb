class AddEntryFieldsToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :entry_date, :date
    add_column :visitor_submissions, :arrival_date, :date
  end
end
