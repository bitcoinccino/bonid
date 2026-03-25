# db/migrate/20250912001000_migrate_role_int_to_roles.rb
class MigrateRoleIntToRoles < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Migrating role_int into roles table" do
      User.reset_column_information
      User.find_each do |user|
        case user.role_int
        when 0
          user.roles.find_or_create_by!(name: "citizen")
        when 1
          user.roles.find_or_create_by!(name: "admin")
        when 2
          user.roles.find_or_create_by!(name: "partner_admin")
        when 3
          user.roles.find_or_create_by!(name: "officer")
        when 4
          user.roles.find_or_create_by!(name: "reviewer")
        else
          Rails.logger.info "Skipping user #{user.id} with role_int #{user.role_int.inspect}"
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
