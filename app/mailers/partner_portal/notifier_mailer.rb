# app/mailers/partner_portal/notifier_mailer.rb
module PartnerPortal
  class NotifierMailer < VerifyemMailer
    default from: "noreply@verifyem.ht"

    # === Notify User When Their BonID Was Scanned ===
    def bonid_scanned(user:, partner:)
      @user    = user
      @partner = partner

      mail(
        to: @user.email,
        subject: "Your BonID was accessed by #{@partner.name}"
      )
    end
  end
end
