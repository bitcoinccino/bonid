class AddVerifiedByToQrScans < ActiveRecord::Migration[8.0]
  def change
    add_column :qr_scans, :verified_by, :string
  end
end
