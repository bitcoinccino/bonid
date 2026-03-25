# db/migrate/20251108111500_add_currently_open_to_bank_profiles.rb
class AddCurrentlyOpenToBankProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_profiles, :currently_open, :boolean,
      default: true,
      null: false,
      comment: "Indicates whether the account or wallet is still active/open."

    add_index :bank_profiles, :currently_open
  end
end
