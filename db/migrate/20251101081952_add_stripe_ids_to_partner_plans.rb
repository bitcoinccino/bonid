class AddStripeIdsToPartnerPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_plans, :stripe_price_id, :string  # Links to Stripe Price object
    add_column :partner_plans, :stripe_product_id, :string  # Links to Stripe Product
    add_index :partner_plans, :stripe_price_id  # For fast lookups
  end
end
