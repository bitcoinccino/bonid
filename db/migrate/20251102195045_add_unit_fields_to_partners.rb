class AddUnitFieldsToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :unit_type, :string
    add_column :partners, :unit_name, :string
    add_index :partners, :unit_type  # For fast queries on law enforcement
  end
end
