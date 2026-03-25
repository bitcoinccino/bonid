class AddTrackableToOfficers < ActiveRecord::Migration[8.0]
  def change
    add_column :officers, :sign_in_count, :integer, default: 0, null: false
    add_column :officers, :current_sign_in_at, :datetime
    add_column :officers, :last_sign_in_at, :datetime
    add_column :officers, :current_sign_in_ip, :inet
    add_column :officers, :last_sign_in_ip, :inet
  end
end
