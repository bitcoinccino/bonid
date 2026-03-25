class AddPrefixAndSuffixToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :prefix, :string
    add_column :users, :suffix, :string
  end
end
