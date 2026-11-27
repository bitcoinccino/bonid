# frozen_string_literal: true

# Diaspora location below the country: US state (ISO code, e.g. "FL") and
# city ("Miami"). Lets the admin see demand by state/city like by commune.
class AddResidenceStateAndCityToWaitlistSignups < ActiveRecord::Migration[8.0]
  def change
    add_column :waitlist_signups, :residence_state, :string, limit: 3
    add_column :waitlist_signups, :residence_city, :string, limit: 80
  end
end
