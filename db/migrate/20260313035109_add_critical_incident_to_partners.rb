class AddCriticalIncidentToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :critical_incident_active, :boolean, default: false, null: false
    add_column :partners, :critical_incident_message, :string
    add_column :partners, :critical_incident_activated_at, :datetime
  end
end
