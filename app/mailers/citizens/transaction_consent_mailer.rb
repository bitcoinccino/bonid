# frozen_string_literal: true

module Citizens
  class TransactionConsentMailer < Citizens::BaseMailer
    default from: "bonid@verifyem.ht"
    layout "mailer"

    def consent_request
      @consent = params[:consent]
      @otp = params[:otp]
      @citizen = @consent.citizen
      @partner = @consent.partner
      @email_product = "bonid"
      @email_badge = "TRANSACTION"
      mail(
        to: @citizen.email,
        subject: t("mailers.transaction_consent.consent_request.subject", partner_name: @partner.name)
      )
    end

    def consent_approved
      @consent = params[:consent]
      @citizen = @consent.citizen
      @partner = @consent.partner
      @email_product = "bonid"
      @email_badge = "TRANSACTION"
      mail(
        to: @citizen.email,
        subject: t("mailers.transaction_consent.consent_approved.subject", partner_name: @partner.name)
      )
    end

    def consent_denied
      @consent = params[:consent]
      @citizen = @consent.citizen
      @partner = @consent.partner
      @email_product = "bonid"
      @email_badge = "TRANSACTION"
      mail(
        to: @citizen.email,
        subject: t("mailers.transaction_consent.consent_denied.subject", partner_name: @partner.name)
      )
    end

    def consent_reminder
      @consent = params[:consent]
      @otp = params[:otp]
      @citizen = @consent.citizen
      @partner = @consent.partner
      @email_product = "bonid"
      @email_badge = "TRANSACTION"
      mail(
        to: @citizen.email,
        subject: t("mailers.transaction_consent.consent_reminder.subject", partner_name: @partner.name)
      )
    end
  end
end
