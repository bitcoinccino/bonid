class AddPhoneCountryCodeToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :phone_country_code, :string
  end
end
