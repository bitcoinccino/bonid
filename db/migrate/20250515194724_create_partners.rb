class CreatePartners < ActiveRecord::Migration[7.1]
  def change
    create_table :partners do |t|
      t.string :name
      t.string :contact_person
      t.string :email
      t.string :sector
      t.string :slug
      t.datetime :verified_at
      t.string :use_cases, array: true, default: []

      t.timestamps
    end
  end
end
