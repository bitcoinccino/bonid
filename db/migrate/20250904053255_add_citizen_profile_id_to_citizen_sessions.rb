class AddCitizenProfileIdToCitizenSessions < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:citizen_sessions, :citizen_profile_id)
      add_column :citizen_sessions, :citizen_profile_id, :bigint
      add_index :citizen_sessions, :citizen_profile_id
    end
  end
end
