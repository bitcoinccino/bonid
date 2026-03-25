class AddTargetAudienceAndMetadataToPartnerPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :partner_plans, :target_audience, :string unless column_exists?(:partner_plans, :target_audience)
    add_column :partner_plans, :metadata, :jsonb, default: {} unless column_exists?(:partner_plans, :metadata)
  end
end
