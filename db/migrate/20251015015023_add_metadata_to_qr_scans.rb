class AddMetadataToQrScans < ActiveRecord::Migration[8.0]
  def change
    add_column :qr_scans, :metadata, :jsonb
  end
end
