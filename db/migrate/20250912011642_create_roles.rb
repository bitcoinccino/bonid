# db/migrate/20250912000000_create_roles.rb
class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false # e.g. "citizen", "admin", "officer"
      t.timestamps
    end

    # Prevent duplicates: one user cannot have the same role twice
    add_index :roles, [ :user_id, :name ], unique: true
  end
end
