class AddSwiftCodeToBankAccounts < ActiveRecord::Migration[7.1]
  def change
    # Only add the column if it doesn’t exist (safe reruns)
    add_column :bank_accounts, :swift_code, :string unless column_exists?(:bank_accounts, :swift_code)

    # Optional: add an index for lookup or performance
    add_index :bank_accounts, :swift_code unless index_exists?(:bank_accounts, :swift_code)
  end
end
