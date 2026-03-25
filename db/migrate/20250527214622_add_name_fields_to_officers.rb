class AddNameFieldsToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :first_name, :string
    add_column :officers, :middle_name, :string
    add_column :officers, :last_name, :string
  end
end
