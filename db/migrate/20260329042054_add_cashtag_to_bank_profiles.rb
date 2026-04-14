class AddCashtagToBankProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_profiles, :cashtag, :string
  end
end
