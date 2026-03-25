# frozen_string_literal: true

module Api
  module V1
    class CitizenConsentsController < ActionController::API
      # ✅ Stateless API controller, no CSRF protection required
      protect_from_forgery with: :null_session if respond_to?(:protect_from_forgery)

      # === GET or POST /api/v1/citizen/approve_consent
      def approve
        token    = params[:grant_token].to_s.strip
        decision = params[:decision].to_s.downcase.presence || "approve"
        scopes   = Array(params[:scopes])
        Rails.logger.info "[CitizenConsent] 🚀 Approve route reached with decision=#{decision}"

        grant = ConsentGrant.find_by(grant_token: token)
        return render_error("Invalid or expired token", :not_found) unless grant

        case decision
        when "approve"
          grant.grant!(scopes: scopes.presence || grant.requested_scopes)
          grant.reload
          Citizens::ConsentMailer.with(grant: grant).approval_confirmation.deliver_later

          # 🔗 Auto-create linked BankAccount if partner is a bank
          partner_bank = grant.partner.try(:bank) || Bank.lookup_by_name(grant.partner.name).first
          if partner_bank.present?
            BankAccount.find_or_create_by!(
              user: grant.citizen,
              bank: partner_bank,
              bank_name: partner_bank.name,
              currency: "HTG",
              account_type: :checking,
              access_level: :partners_access
            ) do |acc|
              acc.account_number = SecureRandom.random_number(10**8).to_s.rjust(8, "0")
            end
          end

          respond_to do |format|
            format.json { render_success(grant, "Consent approved successfully") }
            format.html { render_html(grant, "Consent Approved ✅", :approved) }
          end

        when "reject", "deny"
          grant.revoke!(reason: "Citizen denied via consent portal")
          grant.reload
          Citizens::ConsentMailer.with(grant: grant).denial_notification.deliver_later

          respond_to do |format|
            format.json { render json: { message: "Consent request denied", status: grant.status }, status: :ok }
            format.html { render_html(grant, "Consent Rejected ❌", :rejected) }
          end

        else
          render_error("Invalid decision. Must be 'approve' or 'reject'.", :unprocessable_entity)
        end

      rescue => e
        Rails.logger.error("[CitizenConsent] #{e.class}: #{e.message}")
        render_error(e.message, :internal_server_error)
      end

      private

      # === JSON success renderer
      def render_success(grant, message)
        render json: {
          message: message,
          status: grant.status,
          partner: grant.partner.name,
          citizen: {
            bonid: grant.citizen.bonid,
            name:  "#{grant.citizen.first_name} #{grant.citizen.last_name}"
          },
          approved_scopes: grant.scopes,
          granted_at: grant.granted_at
        }, status: :ok
      end

      # === HTML renderer for approval / rejection pages
      def render_html(grant, title, type)
        color = type == :approved ? "#00209F" : "#E53E3E"
        subtext = type == :approved ? "has been processed successfully." : "has been declined."

        html = <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <title>BonID Consent</title>
            <style>
              @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@500;600&display=swap');
              body {
                font-family: 'Montserrat', sans-serif;
                background: #f8f9fa;
                color: #222;
                text-align: center;
                padding: 60px;
              }
              .card {
                background: white;
                border-radius: 16px;
                padding: 40px 60px;
                display: inline-block;
                box-shadow: 0 4px 20px rgba(0,0,0,0.08);
                max-width: 600px;
              }
              h1 {
                color: #{color};
                font-weight: 700;
                font-size: 28px;
                margin-bottom: 12px;
              }
              p {
                color: #444;
                font-size: 15px;
                line-height: 1.6;
              }
              .partner {
                font-weight: 600;
                color: #{color};
              }
              a {
                display: inline-block;
                margin-top: 25px;
                padding: 12px 22px;
                background: #{color};
                color: white;
                border-radius: 8px;
                text-decoration: none;
                font-weight: 600;
              }
              a:hover {
                background: #001b87;
              }
            </style>
          </head>
          <body>
            <div class="card">
              <h1>#{title}</h1>
              <p>Your consent for <span class="partner">#{grant.partner.name}</span> #{subtext}</p>
              <p>BonID No: <strong>#{grant.citizen.bonid}</strong></p>
              <p>Scopes: #{grant.requested_scopes.join(', ')}</p>
              <a href="https://bonid.ht">Return to BonID</a>
            </div>
          </body>
          </html>
        HTML

        render inline: html, content_type: "text/html"
      end

      # === Error HTML renderer
      def render_error(msg, status)
        render inline: <<~HTML, content_type: "text/html", status: status
          <html><body style="text-align:center;padding:40px;font-family:Montserrat,Arial;color:#00209F;">
            <h1>⚠️ Error</h1>
            <p>#{msg}</p>
            <a href="https://bonid.ht" style="color:#00209F;text-decoration:none;font-weight:600;">Return to BonID</a>
          </body></html>
        HTML
      end
    end
  end
end
