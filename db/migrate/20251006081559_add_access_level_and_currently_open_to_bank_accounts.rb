class AddAccessLevelAndCurrentlyOpenToBankAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_accounts, :access_level, :integer, default: 0, null: false
    add_column :bank_accounts, :currently_open, :boolean, default: true, null: false
  end
end
