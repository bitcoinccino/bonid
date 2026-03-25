class AddVisitorQrToVisitorSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :visitor_submissions, :visitor_qr_png_base64, :text
  end
end
