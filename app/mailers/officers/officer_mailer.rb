# app/mailers/officers/officer_mailer.rb
module Officers
  class OfficerMailer < Devise::Mailer
    include Devise::Mailers::Helpers
    include Rails.application.routes.url_helpers

    default from: "idpol@verifyem.ht"
    layout "mailer"

    def invitation_email(officer, token, host_options = {})
      @officer = officer
      @partner = officer.partner
      @email_product = "idpol"

      # Build invitation link - use passed host options or fall back to config
      @invitation_link = build_invitation_url(token, host_options)

      @rank_title = @officer.rank.present? ? "#{@officer.rank} #{@officer.last_name}" : @officer.last_name

      # Inline PNH logo for email
      logo_path = Rails.root.join("app", "assets", "images", "pnh.png")
      attachments.inline["pnh.png"] = File.read(logo_path) if File.exist?(logo_path)

      mail(
        to: @officer.email,
        subject: "IDPol: Aksyon Nesesè — Envitasyon Pòtay Ofisye #{@partner.name}"
      ) do |format|
        format.html # will look for invitation_email.html.erb
        format.text # will look for invitation_email.text.erb
      end
    end

    # Alert supervisor about overdue incident report review
    def overdue_review_alert
      @review = params[:review]
      @reviewer = params[:reviewer]
      @incident_report = @review.incident_report
      @email_product = "idpol"

      mail(
        to: @reviewer.email,
        subject: "IDPol: Overdue — Incident Report Review Required - #{@incident_report.report_id}"
      )
    end

    # Notify supervisor about new report requiring review
    def new_report_for_review
      @review = params[:review]
      @reviewer = params[:reviewer]
      @incident_report = @review.incident_report
      @email_product = "idpol"

      mail(
        to: @reviewer.email,
        subject: "📋 New Incident Report Requires Review - #{@incident_report.report_id}"
      )
    end

    # Daily summary of pending reviews for supervisors
    def daily_review_summary
      @reviewer = params[:reviewer]
      @summary = params[:summary]
      @email_product = "idpol"

      mail(
        to: @reviewer.email,
        subject: "📊 Daily Review Summary - #{@summary[:total_pending]} Pending Reports"
      )
    end

    private

    def build_invitation_url(token, host_options)
      opts = host_options.presence || default_url_options
      host = opts[:host]
      protocol = opts[:protocol] || "https"
      port = opts[:port]

      # Build base URL - exclude port for ngrok/tunnels
      base = "#{protocol}://#{host}"
      base += ":#{port}" if port.present? && !host.to_s.include?("ngrok")

      "#{base}/officers/invitation/accept?invitation_token=#{token}"
    end

    def default_url_options
      Rails.application.config.action_mailer.default_url_options || {}
    end
  end
end

# #bonid/app/mailers/officer_mailer.rb
# class OfficerMailer < Devise::Mailer
#   include Devise::Mailers::Helpers
#   include Rails.application.routes.url_helpers

#   default from: "admin@bonid.com"

#   def default_url_options
#     {
#       host: Rails.application.config.action_mailer.default_url_options[:host],
#       protocol: Rails.application.config.action_mailer.default_url_options[:protocol]
#     }
#   end

#   # 🔑 Devise-style manual invitation email
#   def invitation_email(officer, token)
#     @officer = officer
#     @invitation_link = accept_officer_invitation_url(invitation_token: token)

#     mail(
#       to: @officer.email,
#       subject: "You're invited to join BonID"
#     )
#   end

#   def invitation_email(user, token)
#     @user = user
#     @partner = user.partner
#     @reset_url = edit_user_password_url(reset_password_token: token)

#     mail(
#       to: @user.email,
#       subject: "You're invited to join the BonID Officer Portal"
#     )
#   end
# end
