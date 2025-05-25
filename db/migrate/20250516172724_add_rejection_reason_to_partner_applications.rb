class AddRejectionReasonToPartnerApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_applications, :rejection_reason, :string
  end
end
