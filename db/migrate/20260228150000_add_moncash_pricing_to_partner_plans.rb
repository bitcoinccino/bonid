# frozen_string_literal: true

class AddMoncashPricingToPartnerPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :partner_plans, :price_htg, :decimal, precision: 10, scale: 2, default: 0
    add_column :partner_plans, :price_per_extra_verif_htg, :decimal, precision: 10, scale: 2, default: 0
    add_column :partner_plans, :price_per_extra_admin_htg, :decimal, precision: 10, scale: 2, default: 0
    add_column :partner_plans, :rate_limit, :integer, default: 20, comment: "API requests per minute (or per day for free)"
  end
end
