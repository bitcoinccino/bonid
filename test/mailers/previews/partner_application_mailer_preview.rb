# Preview all emails at http://localhost:3000/rails/mailers/partner_application_mailer
class PartnerApplicationMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/partner_application_mailer/confirmation
  def confirmation
    PartnerApplicationMailer.confirmation
  end
end
