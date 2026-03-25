class AddAccommodationFieldsToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :accommodation_name, :string
    add_column :visitor_submissions, :accommodation_type, :string
  end
end
