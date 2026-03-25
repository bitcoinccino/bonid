class AddDivisionFieldsToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_column :addresses, :department_id, :bigint
    add_column :addresses, :arrondissement_id, :bigint
  end
end
