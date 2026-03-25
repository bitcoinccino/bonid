# db/migrate/20251108105000_add_linked_at_to_bank_profiles.rb
class AddLinkedAtToBankProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_profiles, :linked_at, :datetime, comment: "Timestamp when the user linked this bank/wallet profile"
    add_index  :bank_profiles, :linked_at
  end
end
