class AddLocationFieldsToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :communal_section, :string
    add_column :partners, :street_address, :string
    add_column :partners, :postal_code, :string
    add_column :partners, :commune, :string
    add_column :partners, :department, :string
    add_column :partners, :country, :string
    add_column :partners, :latitude, :float
    add_column :partners, :longitude, :float
  end
end
