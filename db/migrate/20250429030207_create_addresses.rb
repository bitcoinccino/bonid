class CreateAddresses < ActiveRecord::Migration[8.0]
  def change
    create_table :addresses do |t|
      t.string :street_address
      t.references :communal_section, null: false, foreign_key: true

      t.timestamps
    end
  end
end
