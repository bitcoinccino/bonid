# frozen_string_literal: true

# Language the person signed up in (en/fr/ht), so waitlist emails can be
# sent in that language instead of all three.
class AddLocaleToWaitlistSignups < ActiveRecord::Migration[8.0]
  def change
    add_column :waitlist_signups, :locale, :string, limit: 5
  end
end
