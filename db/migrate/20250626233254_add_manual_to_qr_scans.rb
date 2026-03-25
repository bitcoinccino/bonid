class AddManualToQrScans < ActiveRecord::Migration[8.0]
  def change
    add_column :qr_scans, :manual, :boolean
  end
end
