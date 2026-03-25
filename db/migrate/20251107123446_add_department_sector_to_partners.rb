class AddDepartmentSectorToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :department_sector, :string
  end
end
