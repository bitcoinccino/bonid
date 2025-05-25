class AddCommuneIdToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_column :addresses, :commune_id, :bigint
  end
end
