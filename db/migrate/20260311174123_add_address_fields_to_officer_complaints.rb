class AddAddressFieldsToOfficerComplaints < ActiveRecord::Migration[8.0]
  def change
    add_reference :officer_complaints, :arrondissement, null: true, foreign_key: true
    add_column :officer_complaints, :street_address, :string
    add_column :officer_complaints, :locality, :string
    add_column :officer_complaints, :postal_code, :string
    add_column :officer_complaints, :country, :string, default: "Haiti"
  end
end
