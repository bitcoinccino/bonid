class CreateRolesAdminUsersJoinTable < ActiveRecord::Migration[8.0]
  def change
    create_join_table :roles, :admin_users do |t|
      # t.index [:role_id, :admin_user_id]
      # t.index [:admin_user_id, :role_id]
    end
  end
end
