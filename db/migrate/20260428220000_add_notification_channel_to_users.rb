class AddNotificationChannelToUsers < ActiveRecord::Migration[8.0]
  def change
    # Citizen settings: which channel they prefer for BonID notifications.
    # Defaults to email — phone is unlocked once the citizen adds a phone
    # number to their profile (the settings UI greys it out otherwise).
    add_column :users, :notification_channel, :string, default: "email"
  end
end
