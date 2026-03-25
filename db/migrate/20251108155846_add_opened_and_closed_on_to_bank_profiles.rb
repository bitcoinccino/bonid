# db/migrate/20251108131500_add_opened_and_closed_on_to_bank_profiles.rb
class AddOpenedAndClosedOnToBankProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_profiles, :opened_on, :date, comment: "Date when account or wallet was opened"
    add_column :bank_profiles, :closed_on, :date, comment: "Date when account or wallet was closed"
  end
end
