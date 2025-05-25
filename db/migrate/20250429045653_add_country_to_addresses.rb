class AddCountryToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_column :addresses, :country, :string
  end
end
