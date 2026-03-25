class CreateLocalContacts < ActiveRecord::Migration[7.1]
  def change
    create_table :local_contacts do |t|
      t.string  :name, null: false
      t.string  :phone
      t.string  :email
      t.string  :relationship
      t.boolean :verified, default: false, null: false

      # BonID linkage
      t.string :bonid
      t.references :user, foreign_key: true, null: true

      t.timestamps
    end

    add_index :local_contacts, :bonid
  end
end
