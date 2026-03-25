class AddNinuToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :ninu, :string, limit: 10
    add_index :users, :ninu
  end
end
