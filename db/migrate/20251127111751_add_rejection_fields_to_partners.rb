class AddRejectionFieldsToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :rejection_reason, :text
    add_column :partners, :rejection_comment, :text
  end
end
