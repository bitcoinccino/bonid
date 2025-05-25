class AddWelcomeEmailSentToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :welcome_email_sent, :boolean
  end
end
