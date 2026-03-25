module Citizens
  class ConsentMailer < Citizens::BaseMailer
    default from: "bonid@verifyem.ht"
    layout "mailer"

    def request_notification
      @grant = params[:grant]
      @citizen = @grant.citizen
      @partner = @grant.partner
      @email_product = "bonid"
      mail(to: @citizen.email, subject: t("mailers.consent.request_notification.subject", partner_name: @partner.name))
    end

    def approval_confirmation
      @grant = params[:grant]
      @citizen = @grant.citizen
      @partner = @grant.partner
      @email_product = "bonid"
      mail(to: @citizen.email, subject: t("mailers.consent.approval_confirmation.subject", partner_name: @partner.name))
    end

    def denial_notification
      @grant = params[:grant]
      @citizen = @grant.citizen
      @partner = @grant.partner
      @email_product = "bonid"
      mail(to: @citizen.email, subject: t("mailers.consent.denial_notification.subject", partner_name: @partner.name))
    end
  end
end
