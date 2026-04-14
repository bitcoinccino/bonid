class AddPricingToPartnerSchemas < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_schemas, :pricing_type, :string, default: "free"
    add_column :partner_schemas, :price_cents, :integer, default: 0
    add_column :partner_schemas, :currency, :string, default: "HTG"
    add_column :partner_schemas, :service_icon, :string, default: "ri-file-text-line"
    add_column :partner_schemas, :service_category, :string, default: "verification"
    add_column :partner_schemas, :position, :integer, default: 0
    add_column :partner_schemas, :citizen_facing, :boolean, default: false

    add_index :partner_schemas, [:partner_id, :citizen_facing]
    add_index :partner_schemas, [:citizen_facing, :active]
  end
end
