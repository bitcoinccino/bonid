class AddDepartmentToCommunes < ActiveRecord::Migration[8.0]
  def change
    add_reference :communes, :department, null: false, foreign_key: true
  end
end
