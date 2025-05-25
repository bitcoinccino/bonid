class CreateArrondissements < ActiveRecord::Migration[8.0]
  def change
    create_table :arrondissements do |t|
      t.string :name
      t.integer :postal_code_digit
      t.references :department, null: false, foreign_key: true

      t.timestamps
    end
  end
end
