class AddSlugToDepartments < ActiveRecord::Migration[8.0]
  def change
    add_column :departments, :slug, :string
    add_index :departments, :slug, unique: true
  end
end
