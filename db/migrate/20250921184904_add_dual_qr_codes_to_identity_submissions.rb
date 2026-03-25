class AddDualQrCodesToIdentitySubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :identity_submissions, :public_qr_png_base64, :text
    add_column :identity_submissions, :secure_qr_png_base64, :text
  end
end
