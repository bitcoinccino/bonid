class AddQrPngBase64ToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :qr_png_base64, :text
  end
end
