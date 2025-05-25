class AddRecoverableToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :reset_password_token, :string
    add_index :officers, :reset_password_token
    add_column :officers, :reset_password_sent_at, :datetime
  end
end
