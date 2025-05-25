class AddGeoFieldsToQrScans < ActiveRecord::Migration[8.0]
  def change
    add_column :qr_scans, :country, :string
    add_column :qr_scans, :city, :string
    add_column :qr_scans, :region, :string
    add_column :qr_scans, :organization, :string
  end
end
