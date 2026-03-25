class CreateCitizenProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :citizen_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :bonid
      t.jsonb :metadata

      t.timestamps
    end
    add_index :citizen_profiles, :bonid
  end
end
