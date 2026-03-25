class CreatePermissions < ActiveRecord::Migration[7.1]
  def change
    create_table :permissions do |t|
      t.string :action, null: false
      t.string :description
      t.timestamps
    end

    create_table :permissions_roles, id: false do |t|
      t.references :permission, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
    end

    add_index :permissions, :action, unique: true
    add_index :permissions_roles, [ :permission_id, :role_id ], unique: true
  end
end
