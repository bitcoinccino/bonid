class CreateOfficers < ActiveRecord::Migration[7.1]
  def change
    create_table :officers do |t|
      t.string :full_name, null: false
      t.string :badge_id, null: false
      t.string :rank
      t.string :unit_name
      t.string :unit_type
      t.references :partner, null: false, foreign_key: true
      t.references :department, foreign_key: true
      t.references :arrondissement, foreign_key: true
      t.references :commune, foreign_key: true
      t.references :communal_section, foreign_key: true

      t.string :email, null: false
      t.string :phone_number
      t.boolean :approved, default: false
      t.datetime :invited_at
      t.datetime :approved_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :officers, :badge_id, unique: true
    add_index :officers, :email, unique: true
  end
end
