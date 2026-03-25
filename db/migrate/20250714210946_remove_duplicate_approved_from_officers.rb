class RemoveDuplicateApprovedFromOfficers < ActiveRecord::Migration[7.1]
  def change
    remove_column :officers, :approved, :boolean
  end
end
