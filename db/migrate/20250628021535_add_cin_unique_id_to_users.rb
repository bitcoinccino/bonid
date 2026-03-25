class AddCinUniqueIdToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :cin_unique_id, :string
  end
end
