class CreateBanks < ActiveRecord::Migration[8.0]
  def change
    create_table :banks do |t|
      t.string  :name,          null: false
      t.string  :swift_code,    null: false, index: { unique: true }
      t.string  :slug,          null: false, index: true
      t.string  :country,       default: "Haiti", null: false
      t.boolean :verified_partner, default: false, null: false
      t.string  :integration_url

      t.timestamps
    end
  end
end
