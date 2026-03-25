class UpgradeRolifyStructure < ActiveRecord::Migration[7.1]
  def change
    # === Add polymorphic resource columns to roles ===
    unless column_exists?(:roles, :resource_type)
      add_column :roles, :resource_type, :string
      add_index  :roles, :resource_type
    end

    unless column_exists?(:roles, :resource_id)
      add_column :roles, :resource_id, :integer
      add_index  :roles, :resource_id
    end

    # === Ensure join table exists ===
    unless table_exists?(:users_roles)
      create_table(:users_roles, id: false) do |t|
        t.references :user, null: false, foreign_key: true
        t.references :role, null: false, foreign_key: true
      end
    end

    # === Add indexes for performance ===
    unless index_exists?(:roles, :name)
      add_index(:roles, :name)
    end

    unless index_exists?(:users_roles, [ :user_id, :role_id ])
      add_index(:users_roles, [ :user_id, :role_id ])
    end
  end
end
