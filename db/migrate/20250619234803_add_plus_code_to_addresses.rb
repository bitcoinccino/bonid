class AddPlusCodeToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_column :addresses, :plus_code, :string
  end
end
