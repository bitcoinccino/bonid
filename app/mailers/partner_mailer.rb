# app/mailers/partner_mailer.rb
class PartnerMailer < ApplicationMailer
  default from: "support@bonid.ht"

  def approved(partner)
    @partner = partner
    @partner_link = start_verification_url(partner: @partner.slug)

    mail(
      to: @partner.email,
      subject: "Your BonID Partner Access is Approved – Start Verifying Users"
    )
  end
end
