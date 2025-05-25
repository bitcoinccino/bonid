class AddPartnerToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_reference :addresses, :partner, foreign_key: true, null: true
  end
end
