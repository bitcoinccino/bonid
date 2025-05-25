class AddContactCodeToPartnerApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_applications, :contact_code, :string
  end
end
