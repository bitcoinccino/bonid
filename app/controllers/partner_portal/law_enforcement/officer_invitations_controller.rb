# frozen_string_literal: true

module PartnerPortal
  module LawEnforcement
    class OfficerInvitationsController < PartnerPortal::LawEnforcement::BaseController
      layout "partner_portal/law_enforcement"
      before_action :ensure_correct_sector

      def new
        @officer = User.new
      end

      def create
        email = officer_params[:email].to_s.strip.downcase
        existing = User.find_by(email: email)

        if existing
          @officer = existing

          # ============================================================
          # ENFORCE: Officer MUST have a verified BonID to be invited
          # ============================================================
          if existing.identity_submissions.approved.none?
            flash[:error] = "This user does not have a verified BonID. Officers must have an approved BonID before they can be invited to the force."
            return redirect_to partner_portal_law_enforcement_officers_path
          end

          existing.add_role("officer")
          existing.update!(partner_id: @current_partner.id) unless existing.partner_id == @current_partner.id

          raw_token, digested_token = Devise.token_generator.generate(User, :invitation_token)
          existing.update!(
            invitation_token:      digested_token,
            invitation_created_at: Time.current,
            invitation_sent_at:    Time.current
          )

          Officers::OfficerMailer.invitation_email(existing, raw_token, mailer_host_options).deliver_later

          AuditLog.create!(
            record: @current_partner,
            action: "send_officer_invitation",
            description: "Sent invitation to verified officer #{existing.email} (BonID verified) for partner #{@current_partner.name} (ID: #{@current_partner.id})"
          )

          flash[:success] = "Invitation sent to verified officer #{existing.full_name || existing.email}."
          return redirect_to partner_portal_law_enforcement_officers_path
        end

        # ============================================================
        # NEW USER: Cannot invite someone without existing BonID
        # They must first register as a citizen and get BonID approved
        # ============================================================
        flash[:error] = "No citizen found with this email. The person must first register on BonID and have their identity verified before they can be invited as an officer."
        redirect_to partner_portal_law_enforcement_officers_path
      end

      # === Bulk invite (CSV upload) ===
      def bulk_new
        # Render bulk invite form
      end

      def bulk_create
        unless params[:file].present?
          flash[:error] = "Please select a CSV file to upload."
          return redirect_to bulk_new_partner_portal_law_enforcement_officer_invitations_path
        end

        csv_file = params[:file]
        emails = csv_file.read.split(/[\r\n,]+/).map(&:strip).map(&:downcase).reject(&:blank?).uniq

        if emails.size > 1000
          flash[:error] = "Maximum 1000 emails per batch. You provided #{emails.size}."
          return redirect_to bulk_new_partner_portal_law_enforcement_officer_invitations_path
        end

        results = { sent: 0, skipped_no_bonid: 0, skipped_not_found: 0 }

        emails.each do |email|
          next unless email.match?(URI::MailTo::EMAIL_REGEXP)

          existing = User.find_by(email: email)

          if existing.nil?
            results[:skipped_not_found] += 1
            next
          end

          if existing.identity_submissions.approved.none?
            results[:skipped_no_bonid] += 1
            next
          end

          # Send invitation
          existing.add_role("officer")
          existing.update!(partner_id: @current_partner.id) unless existing.partner_id == @current_partner.id

          raw_token, digested_token = Devise.token_generator.generate(User, :invitation_token)
          existing.update!(
            invitation_token:      digested_token,
            invitation_created_at: Time.current,
            invitation_sent_at:    Time.current
          )

          Officers::OfficerMailer.invitation_email(existing, raw_token, mailer_host_options).deliver_later
          results[:sent] += 1
        end

        AuditLog.create!(
          record: @current_partner,
          action: "bulk_officer_invitation",
          description: "Bulk invitation: #{results[:sent]} sent, #{results[:skipped_no_bonid]} skipped (no BonID), #{results[:skipped_not_found]} not found"
        )

        flash[:success] = "Bulk invitation complete: #{results[:sent]} invitations sent."
        if results[:skipped_no_bonid] > 0 || results[:skipped_not_found] > 0
          flash[:warning] = "#{results[:skipped_no_bonid]} skipped (no verified BonID), #{results[:skipped_not_found]} not found in system."
        end

        redirect_to partner_portal_law_enforcement_officers_path
      end

      private

      def officer_params
        params.require(:user).permit(:email, :first_name, :last_name, :phone_number, :rank, :badge_number)
      end

      # Build host options from the current request (captures ngrok host)
      def mailer_host_options
        host = request.host

        # For ngrok or other tunnels, never include the port (they use standard 443/80)
        is_tunnel = host.include?("ngrok") || host.include?("tunnel")

        # Check X-Forwarded headers (ngrok sets these)
        forwarded_proto = request.headers["X-Forwarded-Proto"]
        protocol = forwarded_proto.presence || (request.ssl? ? "https" : "http")

        opts = { host: host, protocol: protocol }

        # Only include port for local/private IPs (not tunnels)
        unless is_tunnel
          # For local development, include the port if non-standard
          if request.port != 80 && request.port != 443
            opts[:port] = request.port
          end
        end

        opts
      end
    end
  end
end
