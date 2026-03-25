class CreatePersonInvolvements < ActiveRecord::Migration[8.0]
  def change
    create_table :person_involvements do |t|
      t.references :incident_report, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :address, foreign_key: true
      t.string :bonid
      t.string :name
      t.integer :role, default: 4, null: false
      t.boolean :no_bonid, default: false
      t.timestamps
    end
  end
end