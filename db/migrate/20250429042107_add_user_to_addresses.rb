class AddUserToAddresses < ActiveRecord::Migration[8.0]
  def change
    add_reference :addresses, :user, null: false, foreign_key: true
  end
end
