# db/migrate/20251016200000_add_coordinates_to_qr_scans.rb
class AddCoordinatesToQrScans < ActiveRecord::Migration[7.1]
  def change
    add_column :qr_scans, :latitude, :float
    add_column :qr_scans, :longitude, :float
    add_index  :qr_scans, [:latitude, :longitude]
  end
end
