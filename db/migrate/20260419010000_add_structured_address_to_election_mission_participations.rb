# frozen_string_literal: true

# Add structured postal address fields to ElectionMissionParticipation so each
# diaspora mission's address can be rendered per its host country's UPU S42
# format. The mission itself (city/country) is in the static
# HaitianDiplomaticMissions concern; this layer adds the *physical posting
# address* of the consulate/embassy as it operates for THIS election cycle.
#
# Why structured (and not free-text):
#   - Different host countries put the postal code in different positions
#     (US: "City, ST 33130"; FR: "75008 Paris"; BR: "01310-100")
#   - We want to render the address correctly on diaspora locator UI,
#     registration confirmations, and mail-back labels.
#   - A single PostalAddressFormatter service consumes these columns and
#     applies the country-specific S42 rule.
#
# Lat/lng are nullable; they're only used for the diaspora locator map.
class AddStructuredAddressToElectionMissionParticipations < ActiveRecord::Migration[8.0]
  def change
    change_table :election_mission_participations, bulk: true do |t|
      t.string  :street_line1
      t.string  :street_line2
      t.string  :locality       # city/town
      t.string  :region         # state/province/département (blank where N/A)
      t.string  :postal_code
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
    end
  end
end
