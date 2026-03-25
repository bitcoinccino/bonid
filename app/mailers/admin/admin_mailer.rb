# app/mailers/admin/admin_mailer.rb
# frozen_string_literal: true

module Admin
  class AdminMailer < VerifyemMailer
    default from: "noreply@verifyem.ht"

    # === Invite Partner Admin ===
    def partner_admin_invite(user:, token:, partner:)
      @user    = user
      @token   = token
      @partner = partner
      mail(
        to: @user.email,
        subject: "[BonID] Partner Invitation – #{@partner.name}"
      )
    end

    # === Reminder / Re-invite ===
    def partner_admin_reinvite(user:, token:, partner:)
      @user    = user
      @token   = token
      @partner = partner
      mail(
        to: @user.email,
        subject: "[BonID] Reminder: Partner  Invitation – #{@partner.name}"
      )
    end
  end
end
