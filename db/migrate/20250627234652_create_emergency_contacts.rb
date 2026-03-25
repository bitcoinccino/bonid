class CreateEmergencyContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :emergency_contacts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :phone
      t.string :email
      t.string :relation
      t.string :address
      t.string :bonid

      t.timestamps
    end
  end
end
