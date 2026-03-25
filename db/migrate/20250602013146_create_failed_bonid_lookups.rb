class CreateFailedBonidLookups < ActiveRecord::Migration[8.0]
  def change
    create_table :failed_bonid_lookups do |t|
      t.string :bonid
      t.string :verification_token
      t.string :signature
      t.references :officer, null: false, foreign_key: true
      t.string :reason
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
  end
end
