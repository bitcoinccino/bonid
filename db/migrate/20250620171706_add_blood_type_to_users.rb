class AddBloodTypeToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :blood_type, :string
  end
end
