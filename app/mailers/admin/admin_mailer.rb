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

    # === Fraud Alert: Duplicate Identity Detected ===
    def fraud_alert(submission:)
      @submission = submission
      @user = submission.user
      @dedup_data = submission.metadata&.dig("face_dedup") || {}
      @matched_user = User.find_by(id: @dedup_data["matched_user_id"])

      admin_emails = AdminUser.pluck(:email).compact
      return if admin_emails.empty?

      mail(
        to: admin_emails,
        subject: "[BonID] FRAUD ALERT: Duplicate Identity Detected — #{@user&.full_name || 'Unknown'}"
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
