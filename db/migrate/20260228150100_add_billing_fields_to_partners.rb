# frozen_string_literal: true

class AddBillingFieldsToPartners < ActiveRecord::Migration[7.1]
  def change
    # Payment method (moncash, stripe, none)
    add_column :partners, :payment_method, :string, default: "none"

    # Billing cycle tracking
    add_column :partners, :billing_period_start, :datetime
    add_column :partners, :billing_period_end, :datetime

    # Plan status (active, inactive, grace_period, expired)
    add_column :partners, :plan_status, :string, default: "inactive"

    # MonCash-specific
    add_column :partners, :moncash_customer_id, :string

    # Stripe-specific (these were referenced in code but never migrated)
    add_column :partners, :stripe_customer_id, :string
    add_column :partners, :stripe_subscription_id, :string

    # Payment tracking
    add_column :partners, :last_payment_at, :datetime
    add_column :partners, :grace_period_ends_at, :datetime

    # Monthly verification quota tracking
    add_column :partners, :monthly_verifications_used, :integer, default: 0
    add_column :partners, :verifications_reset_at, :datetime

    # Indexes
    add_index :partners, :plan_status
    add_index :partners, :payment_method
    add_index :partners, :stripe_customer_id
    add_index :partners, :moncash_customer_id
    add_index :partners, :billing_period_end
  end
end
