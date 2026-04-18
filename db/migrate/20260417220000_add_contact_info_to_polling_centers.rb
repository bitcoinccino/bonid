# frozen_string_literal: true

# Sant Vòt (polling centers) need a publicly reachable phone + hours line so
# citizens can confirm their BV the morning of, reach the center supervisor
# if lost, or ask about accessibility. This is distinct from the BED/BEK
# office phone on ElectoralOffice — that's for *registration*; this is for
# *election-day voting*.
class AddContactInfoToPollingCenters < ActiveRecord::Migration[8.0]
  def change
    add_column :polling_centers, :contact_phone, :string
    add_column :polling_centers, :contact_hours, :string
  end
end
