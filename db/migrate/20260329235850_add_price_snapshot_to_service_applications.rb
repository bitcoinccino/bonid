class AddPriceSnapshotToServiceApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :service_applications, :price_snapshot, :jsonb, default: {}
  end
end
