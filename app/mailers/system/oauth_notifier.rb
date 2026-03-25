# app/mailers/system/oauth_notifier.rb
module System
  class OauthNotifier < VerifyemMailer
    default from: "noreply@verifyem.ht",
            reply_to: "support@bonid.ht"

    # 🚀 Sent to citizen when a partner requests consent
    def consent_requested(consent_grant)
      @grant = consent_grant
      return unless @grant&.citizen&.email && @grant&.partner&.name

      mail(
        to: @grant.citizen.email,
        subject: "BonID Consent Request from #{@grant.partner.name}"
      )
    end

    # ✅ Sent to partner after citizen approves consent
    def consent_approved(consent_grant)
      @grant = consent_grant
      return unless @grant&.partner&.email

      mail(
        to: @grant.partner.email,
        subject: "Consent Approved by #{@grant.citizen.full_name}"
      )
    end

    # ❌ Sent to partner after citizen revokes consent
    def consent_revoked(consent_grant)
      @grant = consent_grant
      return unless @grant&.partner&.email

      mail(
        to: @grant.partner.email,
        subject: "Consent Revoked by #{@grant.citizen.full_name}"
      )
    end

    # 🚨 SECURITY ALERT: Sent to citizen when consent is revoked
    def consent_revoked_to_citizen(consent_grant)
      @grant = consent_grant
      @citizen = @grant.citizen
      @partner = @grant.partner
      @revoked_at = @grant.revoked_at || Time.current

      return unless @citizen&.email

      mail(
        to: @citizen.email,
        subject: "Security Alert: Data Access Revoked for #{@partner.name}",
        template_name: "consent_revoked_to_citizen"
      )
    end
  end
end
