class AddStaffNotesToServiceApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :service_applications, :staff_notes, :jsonb, default: []
  end
end
