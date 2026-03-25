class CreateHealthProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :health_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :blood_type
      t.text :allergies, array: true, default: []
      t.text :chronic_conditions, array: true, default: []
      t.text :medications, array: true, default: []
      t.boolean :organ_donor, default: false

      t.timestamps
    end
  end
end
