class AddPartnerToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :partner, null: true, foreign_key: true
  end
end
