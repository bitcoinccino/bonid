class AddApprovedToPartnerApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_applications, :approved, :boolean
  end
end
