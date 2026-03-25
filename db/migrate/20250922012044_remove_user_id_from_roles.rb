class RemoveUserIdFromRoles < ActiveRecord::Migration[8.0]
  def change
    remove_reference :roles, :user, null: false, foreign_key: true
  end
end
