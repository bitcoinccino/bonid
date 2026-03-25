class AddNotifyEmergencyContactToPersonInvolvements < ActiveRecord::Migration[8.0]
  def change
    add_column :person_involvements, :notify_emergency_contact, :boolean, default: false, null: false
  end
end
