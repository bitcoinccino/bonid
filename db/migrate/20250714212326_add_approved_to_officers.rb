class AddApprovedToOfficers < ActiveRecord::Migration[7.1]
  def change
    add_column :officers, :approved, :boolean, default: false, null: false
  end
end
