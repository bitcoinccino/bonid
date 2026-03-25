class AddContextFieldsToCitizenSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :citizen_sessions, :login_source, :string   # e.g. "partner:unibank" or "citizen_portal"
    add_column :citizen_sessions, :ip_address, :string
    add_column :citizen_sessions, :user_agent, :string

    add_index :citizen_sessions, :login_source
  end
end
