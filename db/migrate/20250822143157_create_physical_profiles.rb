class CreatePhysicalProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :physical_profiles do |t|
      t.references :user, null: false, foreign_key: true

      # Core Physical Traits
      t.float :weight_kg
      t.float :height_cm
      t.string :race
      t.string :eye_color
      t.string :hair_color
      t.string :body_type
      t.string :skin_tone
      t.string :facial_hair
      t.string :handedness   # left, right, ambidextrous

      # Extra Identifiable Features
      t.boolean :tattoos, default: false
      t.text :scars
      t.text :birthmarks

      t.timestamps
    end
  end
end
