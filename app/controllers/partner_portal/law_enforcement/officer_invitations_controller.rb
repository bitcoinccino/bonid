# frozen_string_literal: true

# PartnerPortal::LawEnforcement::OfficerInvitationsController
# ============================================================
# PNH officer invitation flow.
#
# Same BonID gate as unified team flow:
#   - Lookup by last 6 chars of BonID (no dashes)
#   - Must have verified BonID
#
# Additionally assigns at invite time:
#   - Rank (from OfficerConstants::RANKS)
#   - Unit name (DCPJ, CIMO, SWAT, etc.)
#   - Unit type (specialty within the unit)
#   - Badge number
#
# Officer record created immediately on invite — not on acceptance.

module PartnerPortal
  module LawEnforcement
    class OfficerInvitationsController < PartnerPortal::LawEnforcement::BaseController
      layout "partner_portal/law_enforcement"
      before_action :ensure_correct_sector

      # === INVITE FORM (BonID lookup) ===
      def new
        @officer = User.new
      end

      # === BONID LOOKUP → CONFIRM PAGE ===
      def lookup
        bonid_suffix = params[:bonid].to_s.strip.delete("-").upcase
        @person = TeamInvitationService.lookup(bonid_suffix)

        if @person.nil?
          flash[:error] = "Pa gen moun ak BonID ki fini ak \"#{bonid_suffix}\". Verifye kòd la epi eseye ankò."
          return redirect_to new_partner_portal_law_enforcement_officer_invitation_path
        end

        unless @person[:verified]
          flash[:error] = "#{@person[:full_name]} gen yon kont BonID men li poko verifye."
          return redirect_to new_partner_portal_law_enforcement_officer_invitation_path
        end

        @ranks      = OfficerConstants::RANKS
        @units      = OfficerConstants::UNIT_OPTIONS
        render :confirm
      end

      # === SEND INVITATION ===
      def create
        bonid_suffix = params[:bonid].to_s.strip.delete("-").upcase
        user = TeamInvitationService.find_by_suffix(bonid_suffix)

        unless user
          flash[:error] = "Pa gen moun ak BonID sa a."
          return redirect_to new_partner_portal_law_enforcement_officer_invitation_path
        end

        # ============================================================
        # GATE: Must have verified BonID
        # ============================================================
        unless user.identity_submissions.approved.exists?
          flash[:error] = "#{user.full_name} pa gen yon BonID verifye. Ofisye dwe gen yon BonID apwouve anvan yo ka envite nan fòs la."
          return redirect_to partner_portal_law_enforcement_officers_path
        end

        # ============================================================
        # GATE: Cannot invite yourself
        # ============================================================
        if user.id == current_user.id
          flash[:error] = "Ou pa ka envite tèt ou."
          return redirect_to new_partner_portal_law_enforcement_officer_invitation_path
        end

        # ============================================================
        # ASSIGN: Officer role + create Officer record with unit/rank
        # ============================================================
        ActiveRecord::Base.transaction do
          user.add_role("officer") unless user.has_role?(:officer)
          user.update!(partner_id: @current_partner.id) unless user.partner_id == @current_partner.id

          # Create or update Officer record with rank, unit, badge
          officer = user.officer || user.build_officer
          officer.assign_attributes(
            partner:    @current_partner,
            email:      user.email,
            first_name: user.first_name,
            last_name:  user.last_name,
            rank:       params[:rank],
            unit_name:  params[:unit_name],
            unit_type:  params[:unit_type],
            badge_id:   params[:badge_id].presence || generate_badge_id,
            status:     :invited
          )
          officer.password = SecureRandom.hex(12) if officer.new_record?
          officer.save!(validate: false)

          # Generate invitation token
          raw_token, digested_token = Devise.token_generator.generate(User, :invitation_token)
          user.update!(
            invitation_token:      digested_token,
            invitation_created_at: Time.current,
            invitation_sent_at:    Time.current
          )

          Officers::OfficerMailer.invitation_email(officer, raw_token, mailer_host_options).deliver_later

          AuditLog.create!(
            record: @current_partner,
            action: "send_officer_invitation",
            description: "Envitasyon voye bay #{user.full_name} (#{user.bonid}) — #{params[:rank]} / #{params[:unit_name]} / #{params[:unit_type]}"
          )
        end

        flash[:success] = "Envitasyon voye bay #{user.full_name} — #{params[:rank]}, #{params[:unit_name]}."
        redirect_to partner_portal_law_enforcement_officers_path
      end

      # === Bulk invite (CSV upload) ===
      def bulk_new
        # Render bulk invite form
      end

      def bulk_create
        unless params[:file].present?
          flash[:error] = "Tanpri chwazi yon fichye CSV."
          return redirect_to bulk_new_partner_portal_law_enforcement_officer_invitations_path
        end

        csv_file = params[:file]
        emails = csv_file.read.split(/[\r\n,]+/).map(&:strip).map(&:downcase).reject(&:blank?).uniq

        if emails.size > 1000
          flash[:error] = "Maksimòm 1000 imèl pa lot. Ou bay #{emails.size}."
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
          description: "Envitasyon an mas: #{results[:sent]} voye, #{results[:skipped_no_bonid]} sote (pa gen BonID), #{results[:skipped_not_found]} pa jwenn"
        )

        flash[:success] = "Envitasyon an mas fini: #{results[:sent]} envitasyon voye."
        if results[:skipped_no_bonid] > 0 || results[:skipped_not_found] > 0
          flash[:warning] = "#{results[:skipped_no_bonid]} sote (pa gen BonID verifye), #{results[:skipped_not_found]} pa jwenn nan sistèm nan."
        end

        redirect_to partner_portal_law_enforcement_officers_path
      end

      private

      def generate_badge_id
        "PNH#{SecureRandom.hex(4).upcase}"
      end

      def mailer_host_options
        host = request.host
        is_tunnel = host.include?("ngrok") || host.include?("tunnel")
        forwarded_proto = request.headers["X-Forwarded-Proto"]
        protocol = forwarded_proto.presence || (request.ssl? ? "https" : "http")

        opts = { host: host, protocol: protocol }
        unless is_tunnel
          opts[:port] = request.port if request.port != 80 && request.port != 443
        end
        opts
      end
    end
  end
end
