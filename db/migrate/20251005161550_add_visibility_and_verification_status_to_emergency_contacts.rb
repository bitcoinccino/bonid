class AddVisibilityAndVerificationStatusToEmergencyContacts < ActiveRecord::Migration[7.1]
  def change
    add_column :emergency_contacts, :visibility, :integer, default: 0, null: false  # 0 = private
    add_column :emergency_contacts, :verification_status, :integer, default: 0, null: false  # 0 = unverified
  end
end
