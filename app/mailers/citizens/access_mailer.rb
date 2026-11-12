# frozen_string_literal: true

module Citizens
  # Tells a citizen when a partner starts or stops being able to see their
  # information ("Sign in with BonID" / ongoing access). Sent from
  # ConsentGrant callbacks so every path (dashboard, OAuth, API) is covered.
  class AccessMailer < Citizens::BaseMailer
    default from: "bonid@verifyem.ht"
    layout "mailer"
    helper ConsentScopeLabelsHelper

    def access_granted
      @grant   = params[:grant]
      @partner = @grant.partner
      @citizen = @grant.citizen
      return if @citizen&.email.blank?

      # Sent in the citizen's portal language (Paramèt → Lang).
      I18n.with_locale(@citizen.portal_locale) do
        @email_badge = t("mailers.access.badge")
        mail(to: @citizen.email, subject: t("mailers.access.granted.subject", partner_name: @partner.name))
      end
    end

    def access_removed
      @grant   = params[:grant]
      @partner = @grant.partner
      @citizen = @grant.citizen
      return if @citizen&.email.blank?

      # Sent in the citizen's portal language (Paramèt → Lang).
      I18n.with_locale(@citizen.portal_locale) do
        @email_badge = t("mailers.access.badge")
        mail(to: @citizen.email, subject: t("mailers.access.removed.subject", partner_name: @partner.name))
      end
    end
  end
end
