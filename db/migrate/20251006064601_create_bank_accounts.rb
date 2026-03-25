# db/migrate/20251006_create_bank_accounts.rb
class CreateBankAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :bank_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :bank_name, null: false
      t.string :account_number, null: false
      t.integer :account_type, null: false, default: 0
      t.string :currency, null: false, default: "HTG"
      t.date :opened_on
      t.date :closed_on

      t.timestamps
    end

    add_index :bank_accounts, [ :user_id, :bank_name, :account_number ], unique: true
  end
end
