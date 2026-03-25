# app/mailers/partner_portal/law_enforcement_mailer.rb
module PartnerPortal
  class LawEnforcementMailer < VerifyemMailer
    default from: "idpol@verifyem.ht"

    # === Single Officer Invitation ===
    def single_invite(email:, url:, partner:)
      @partner = partner
      @url     = url
      mail(
        to: email,
        subject: "You're Invited to Join #{@partner.name} as a BonID Officer"
      )
    end

    # === Bulk Officer Invitation ===
    def bulk_invite(email:, url:, partner:)
      @partner = partner
      @url     = url
      mail(
        to: email,
        subject: "Join #{@partner.name} as an Officer on BonID"
      )
    end
  end
end
