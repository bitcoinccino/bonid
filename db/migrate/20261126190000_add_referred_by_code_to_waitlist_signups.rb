# frozen_string_literal: true

# Who shared the link this person signed up through (the referrer's
# referral_code), so referrals can be counted per person.
class AddReferredByCodeToWaitlistSignups < ActiveRecord::Migration[8.0]
  def change
    add_column :waitlist_signups, :referred_by_code, :string
    add_index :waitlist_signups, :referred_by_code
  end
end
