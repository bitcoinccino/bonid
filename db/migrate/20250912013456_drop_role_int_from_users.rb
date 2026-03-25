class DropRoleIntFromUsers < ActiveRecord::Migration[8.0]
  def up
    remove_column :users, :role_int, :integer
  end

  def down
    # If you rollback, add the column back (but note: old data won't be restored).
    add_column :users, :role_int, :integer
  end
end
