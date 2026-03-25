class DropBankAccounts < ActiveRecord::Migration[8.0]
  def up
    drop_table :bank_accounts
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
