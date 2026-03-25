class AddPhoneCountryCodeToLocalContacts < ActiveRecord::Migration[8.0]
  def change
    add_column :local_contacts, :phone_country_code, :string
  end
end
