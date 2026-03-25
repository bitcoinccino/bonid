class AddAccessLevelToBankProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :bank_profiles, :access_level, :string
  end
end
