class AddPartnerIdToPartnerApplications < ActiveRecord::Migration[8.0]
  def change
    add_reference :partner_applications, :partner, foreign_key: true, null: true
  end
end
