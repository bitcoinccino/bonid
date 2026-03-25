class AddIntegerRoleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :role_int, :integer, default: 0 unless column_exists?(:users, :role_int)
  end
end
