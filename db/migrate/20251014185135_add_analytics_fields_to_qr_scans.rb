class AddAnalyticsFieldsToQrScans < ActiveRecord::Migration[8.0]
  def change
    add_column :qr_scans, :method, :string
    add_column :qr_scans, :partner_branch_id, :integer
    add_column :qr_scans, :department_id, :integer
  end
end
