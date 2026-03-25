class AddTemplateAndSectorToPartnerSchemas < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_schemas, :template, :boolean, default: false
    add_column :partner_schemas, :sector, :string  # e.g., 'banking', 'health'
    add_index :partner_schemas, :template
    add_index :partner_schemas, :sector
  end
end
