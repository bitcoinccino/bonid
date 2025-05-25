class PartnerNotifierMailer < ApplicationMailer
  def bonid_scanned(user, partner)
    @user = user
    @partner = partner
    mail(
      to: @user.email,
      subject: "Your BonID was accessed by #{@partner.name}"
    )
  end
end
