# db/migrate/20251108160000_add_account_source_to_bank_profiles.rb
class AddAccountSourceToBankProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_profiles, :account_source, :string, null: false, default: "bank"
    add_index  :bank_profiles, :account_source
  end
end
