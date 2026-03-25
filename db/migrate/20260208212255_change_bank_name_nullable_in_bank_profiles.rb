# db/migrate/20260208212255_change_bank_name_nullable_in_bank_profiles.rb
class ChangeBankNameNullableInBankProfiles < ActiveRecord::Migration[7.1]
  def change
    # Allow bank_name and account_number to be null for mobile/crypto wallets
    change_column_null :bank_profiles, :bank_name, true
    change_column_null :bank_profiles, :account_number, true
  end
end
