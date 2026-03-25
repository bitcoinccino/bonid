class AddApprovedByToPartnerSchemas < ActiveRecord::Migration[7.1]  # Adjust version as needed
  def change
    add_reference :partner_schemas, :approved_by, foreign_key: { to_table: :admin_users }, index: true  # Or foreign_key: true if you want FK constraints
  end
end
