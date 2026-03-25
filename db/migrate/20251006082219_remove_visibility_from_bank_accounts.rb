class RemoveVisibilityFromBankAccounts < ActiveRecord::Migration[8.0]
  def change
    remove_column :bank_accounts, :visibility, :integer
  end
end
