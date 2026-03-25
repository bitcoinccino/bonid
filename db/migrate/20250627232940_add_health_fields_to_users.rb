class AddHealthFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :weight_kg, :integer
    add_column :users, :height_cm, :integer
    add_column :users, :race, :string
    add_column :users, :eye_color, :string
    add_column :users, :hair_color, :string
  end
end
