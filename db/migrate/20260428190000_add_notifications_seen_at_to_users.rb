class AddNotificationsSeenAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :notifications_seen_at, :datetime
  end
end
