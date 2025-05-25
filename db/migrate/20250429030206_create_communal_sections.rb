class CreateCommunalSections < ActiveRecord::Migration[8.0]
  def change
    create_table :communal_sections do |t|
      t.string :name
      t.integer :postal_code_digit
      t.references :commune, null: false, foreign_key: true

      t.timestamps
    end
  end
end
