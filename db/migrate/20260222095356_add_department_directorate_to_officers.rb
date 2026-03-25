class AddDepartmentDirectorateToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :department_directorate, :string
  end
end
