class AddStatusToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :status, :integer, default: 0, null: false
  end
end
