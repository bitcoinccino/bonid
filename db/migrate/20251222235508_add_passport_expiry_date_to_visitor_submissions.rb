class AddPassportExpiryDateToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :passport_expiry_date, :date
  end
end
