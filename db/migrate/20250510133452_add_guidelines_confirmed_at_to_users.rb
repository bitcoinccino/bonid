class AddGuidelinesConfirmedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :guidelines_confirmed_at, :datetime
  end
end
