class AddCodeToCommunes < ActiveRecord::Migration[8.0]
  def change
    add_column :communes, :code, :string
    add_index :communes, :code, unique: true
  end
end
