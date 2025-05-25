class AddQrPngBase64ToIdentitySubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :identity_submissions, :qr_png_base64, :text
  end
end
