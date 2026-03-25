class RenameMethodColumnInQrScans < ActiveRecord::Migration[7.1]
  def change
    rename_column :qr_scans, :method, :scan_method
  end
end
