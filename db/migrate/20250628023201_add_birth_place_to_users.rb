class AddBirthPlaceToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :birth_department_id, :integer
    add_column :users, :birth_commune_id, :integer
  end
end
