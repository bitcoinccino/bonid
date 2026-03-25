# app/mailers/partner_portal/banking_mailer.rb
module PartnerPortal
  class BankingMailer < VerifyemMailer
    default from: "BonID Banking <noreply@verifyem.ht>"

    # === Agent Invitation ===
    def agent_invitation(user)
      @resource = user
      @partner  = user.partner
      @token    = user.raw_invitation_token

      mail(
        to: @resource.email,
        subject: "You’ve been invited to join #{@partner&.name || 'BonID Banking Portal'}"
      )
    end

    # === Access Suspended ===
    def access_suspended(agent)
      @agent   = agent
      @partner = agent.partner

      mail(
        to: @agent.email,
        subject: "Your BonID Banking Access Has Been Suspended"
      )
    end

    # === Access Reactivated ===
    def access_reactivated(agent)
      @agent   = agent
      @partner = agent.partner

      mail(
        to: @agent.email,
        subject: "Your BonID Banking Access Has Been Restored"
      )
    end
  end
end
