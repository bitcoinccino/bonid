class AddExtraPricingFieldsToPartnerPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_plans, :price_per_extra_verif, :decimal
    add_column :partner_plans, :price_per_extra_admin, :decimal
  end
end
