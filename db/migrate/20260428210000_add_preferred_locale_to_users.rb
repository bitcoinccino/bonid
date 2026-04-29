class AddPreferredLocaleToUsers < ActiveRecord::Migration[8.0]
  def change
    # Citizen settings: Haitian Creole (ht) is the default — French (fr)
    # is the only other choice surfaced in the citizen settings page.
    add_column :users, :preferred_locale, :string, default: "ht"
  end
end
