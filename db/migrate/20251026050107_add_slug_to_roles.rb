class AddSlugToRoles < ActiveRecord::Migration[8.0]
  def change
    add_column :roles, :slug, :string
    add_index :roles, :slug
  end
end
