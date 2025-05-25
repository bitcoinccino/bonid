# app/controllers/pdfs_controller.rb
class PdfsController < ApplicationController
  def terms
    pdf = TermsPdf.new
    send_data pdf.render,
              filename: "terms_of_use.pdf",
              type: "application/pdf",
              disposition: "inline"
  end

  def privacy
    pdf = PrivacyPdf.new
    send_data pdf.render,
              filename: "privacy_policy.pdf",
              type: "application/pdf",
              disposition: "inline"
  end
end
