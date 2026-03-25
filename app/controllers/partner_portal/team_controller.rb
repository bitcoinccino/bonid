# frozen_string_literal: true

# PartnerPortal::TeamController
# ==============================
# Unified team management for ALL partner sectors EXCEPT law enforcement.
# PNH uses their own officer invitation flow (ranks, units, badges).
#
# Universal rule: every invitee MUST have a verified BonID.
# Lookup by last 6 chars of BonID — name + email auto-pulled from verified record.
# No email input = no spoofing.
#
# Roles: partner_admin / partner_agent (flat, same for all sectors)
#
# Actions:
#   GET    /partner_portal/team           → index   (list team members)
#   GET    /partner_portal/team/new       → new     (invite form — BonID last 6)
#   POST   /partner_portal/team/lookup    → lookup  (preview user before invite)
#   POST   /partner_portal/team           → create  (send invitation)
#   DELETE /partner_portal/team/:id       → destroy (revoke access)

module PartnerPortal
  class TeamController < PartnerPortal::ApplicationController
    before_action :redirect_law_enforcement
    before_action :set_member, only: [:destroy]

    # === LIST TEAM MEMBERS ===
    def index
      @team_members = @partner.users
                        .includes(:roles, :identity_submissions)
                        .where.not(id: nil)
                        .order(created_at: :desc)

      @admins  = @team_members.select { |u| u.has_role?(:partner_admin) }
      @agents  = @team_members.select { |u| u.has_role?(:partner_agent) && !u.has_role?(:partner_admin) }
      @pending = @team_members.select { |u| u.invitation_accepted_at.nil? && u.invitation_sent_at.present? }
    end

    # === INVITE FORM ===
    def new
      @role_options = role_options
    end

    # === BONID LOOKUP (AJAX or form post) ===
    # Partner admin enters a BonID code → we return the person's name + masked email
    # so they can confirm before sending the invitation.
    def lookup
      @bonid = params[:bonid].to_s.strip
      @person = TeamInvitationService.lookup(@bonid)
      @role_options = role_options

      if @person.nil?
        flash.now[:error] = "Pa gen moun ak BonID \"#{@bonid}\". Verifye kòd la epi eseye ankò."
        return render :new
      end

      unless @person[:verified]
        flash.now[:error] = "#{@person[:full_name]} gen yon kont BonID men li poko verifye."
        return render :new
      end

      # Render the confirmation step with person details
      render :confirm
    end

    # === SEND INVITATION ===
    def create
      result = TeamInvitationService.call(
        partner:     @partner,
        bonid:       params[:bonid],
        role:        params[:role],
        invited_by:  current_user,
        employee_id: params[:employee_id],
        office_code: params[:office_code]
      )

      if result.success?
        flash[:success] = "Envitasyon voye bay #{result.user.full_name}."
        redirect_to partner_portal_team_index_path
      else
        flash[:error] = result.error
        redirect_to new_partner_portal_team_path
      end
    end

    # === REVOKE ACCESS ===
    def destroy
      if @member == current_user
        flash[:error] = "Ou pa ka retire tèt ou nan ekip la."
        return redirect_to partner_portal_team_index_path
      end

      ActiveRecord::Base.transaction do
        @member.remove_role(:partner_admin)
        @member.remove_role(:partner_agent)
        @member.update!(partner_id: nil)

        PartnerAuditLog.create!(
          partner:    @partner,
          admin_user: current_user,
          event:      "team_member_revoked",
          details: {
            revoked_email: @member.email,
            revoked_name:  @member.full_name,
            ip:            request.remote_ip
          }
        )

        TeamMailer.revoked(
          user:    @member,
          partner: @partner,
          role:    "partner_agent"
        ).deliver_later
      end

      flash[:success] = "#{@member.full_name} retire nan ekip la."
      redirect_to partner_portal_team_index_path
    end

    private

    # PNH has their own officer invitation system — don't use this controller
    def redirect_law_enforcement
      sector = (@partner.department_sector || @partner.sector).to_s.downcase
      if %w[pnh law_enforcement].include?(sector)
        redirect_to partner_portal_law_enforcement_officers_path
      end
    end

    def set_member
      @member = @partner.users.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      flash[:error] = "Manm ekip la pa jwenn."
      redirect_to partner_portal_team_index_path
    end

    def role_options
      sector = (@partner.department_sector || @partner.sector).to_s.downcase
      GovernmentRoleConstants.role_options_for(sector)
    end
  end
end
