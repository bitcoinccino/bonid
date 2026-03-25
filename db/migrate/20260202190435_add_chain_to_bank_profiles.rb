class AddChainToBankProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_profiles, :chain, :string
  end
end
