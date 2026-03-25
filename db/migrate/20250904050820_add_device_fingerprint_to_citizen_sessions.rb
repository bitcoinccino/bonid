class AddDeviceFingerprintToCitizenSessions < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:citizen_sessions, :device_fingerprint)
      add_column :citizen_sessions, :device_fingerprint, :string
    end
  end
end
