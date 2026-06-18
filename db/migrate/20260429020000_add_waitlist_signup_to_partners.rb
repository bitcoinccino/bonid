# frozen_string_literal: true

class AddWaitlistSignupToPartners < ActiveRecord::Migration[8.0]
  def change
    add_reference :partners, :waitlist_signup, null: true,
                  foreign_key: { on_delete: :nullify }
  end
end
