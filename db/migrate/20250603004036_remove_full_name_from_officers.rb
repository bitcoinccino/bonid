class RemoveFullNameFromOfficers < ActiveRecord::Migration[8.0]
  def change
    remove_column :officers, :full_name, :string
  end
end
