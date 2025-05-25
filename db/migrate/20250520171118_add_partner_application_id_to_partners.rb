class AddPartnerApplicationIdToPartners < ActiveRecord::Migration[8.0]
  def change
    add_column :partners, :partner_application_id, :bigint
  end
end
