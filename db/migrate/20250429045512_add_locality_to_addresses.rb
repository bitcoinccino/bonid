class AddLocalityToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_column :addresses, :locality, :string
  end
end
