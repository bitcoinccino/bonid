class AddEventDatesToPartnerSchemas < ActiveRecord::Migration[7.1]
  def change
    add_column :partner_schemas, :starts_at, :datetime
    add_column :partner_schemas, :ends_at, :datetime
  end
end
