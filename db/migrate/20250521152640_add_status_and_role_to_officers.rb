class AddStatusAndRoleToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :status, :integer
    add_column :officers, :role, :integer
  end
end
