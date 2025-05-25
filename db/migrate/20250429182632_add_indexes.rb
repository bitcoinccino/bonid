class AddIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :departments, :name, unique: true
    add_index :arrondissements, :name
    add_index :communes, :name
    add_index :communal_sections, :name
  end
end
