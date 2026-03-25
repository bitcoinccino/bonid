class AddDescriptionToPartnerSchemas < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_schemas, :description, :text
  end
end
