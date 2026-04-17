class AddLocationToCitizenSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :citizen_sessions, :city, :string
    add_column :citizen_sessions, :country, :string
  end
end
