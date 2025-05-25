class AddUnitFieldsToPartnerApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_applications, :unit_name, :string
    add_column :partner_applications, :unit_type, :string
  end
end
