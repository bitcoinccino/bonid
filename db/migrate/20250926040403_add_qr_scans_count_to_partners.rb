class AddQrScansCountToPartners < ActiveRecord::Migration[7.1]
  def change
    add_column :partners, :qr_scans_count, :integer, default: 0, null: false
  end
end
