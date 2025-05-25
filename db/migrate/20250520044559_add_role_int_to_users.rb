# db/migrate/XXXXXXXXXXXX_migrate_roles_to_role_int.rb
class MigrateRolesToRoleInt < ActiveRecord::Migration[8.0]
  def up
    role_mapping = { "user" => 0, "admin" => 1, "partner_admin" => 2, "reviewer" => 3 }

    User.reset_column_information
    User.find_each do |user|
      user.update_column(:role_int, role_mapping[user.role]) if role_mapping.key?(user.role)
    end
  end

  def down
    # Optional: reverse mapping
  end
end
