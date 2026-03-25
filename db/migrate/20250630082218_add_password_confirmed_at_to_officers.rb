class AddPasswordConfirmedAtToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :password_confirmed_at, :datetime
  end
end
