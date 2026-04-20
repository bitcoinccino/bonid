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
# Authorization matrix:
#   partner_admin  → can invite, assign roles, suspend, reactivate, revoke anyone except self
#   *_supervisor   → can suspend and reactivate agents/tellers in their sector (NOT admins)
#   agents/tellers → can only view team list
#
# Actions:
#   GET    /partner_portal/team               → index       (list team members)
#   GET    /partner_portal/team/new           → new         (invite form — BonID last 6)
#   POST   /partner_portal/team/lookup        → lookup      (preview user before invite)
#   POST   /partner_portal/team               → create      (send invitation)
#   PATCH  /partner_portal/team/:id/suspend   → suspend     (deactivate member access)
#   PATCH  /partner_portal/team/:id/reactivate→ reactivate  (restore member access)
#   PATCH  /partner_portal/team/:id/role      → update_role (reassign member role)
#   DELETE /partner_portal/team/:id           → destroy     (revoke access entirely)

module PartnerPortal
  class TeamController < PartnerPortal::BaseController
    before_action :set_partner_alias
    before_action :redirect_law_enforcement
    before_action :set_member, only: [ :destroy, :suspend, :reactivate, :update_role ]
    before_action :require_admin!, only: [ :new, :lookup, :create, :destroy, :update_role ]
    before_action :require_admin_or_supervisor!, only: [ :suspend, :reactivate ]

    # === LIST TEAM MEMBERS ===
    def index
      @team_members = @partner.users
                        .includes(:roles, :identity_submissions)
                        .where.not(id: nil)
                        .order(created_at: :desc)

      @admins  = @team_members.select { |u| u.has_role?(:partner_admin) }
      @pending = @team_members.select { |u| u.invitation_accepted_at.nil? && u.invitation_sent_at.present? }

      # Sectors with specialized roles get their own groups
      if onaca_sector?
        @surveyors   = @team_members.select { |u| u.has_role?(:partner_agent_surveyor) && !u.has_role?(:partner_admin) }
        @notaries    = @team_members.select { |u| u.has_role?(:partner_agent_notary) && !u.has_role?(:partner_admin) }
        @supervisors = @team_members.select { |u| u.has_role?(:partner_supervisor) && !u.has_role?(:partner_admin) }
        @agents = []
      elsif banking_sector?
        @bank_agents      = @team_members.select { |u| u.has_role?(:bank_agent) && !u.has_role?(:partner_admin) }
        @bank_tellers     = @team_members.select { |u| u.has_role?(:bank_teller) && !u.has_role?(:partner_admin) }
        @bank_supervisors = @team_members.select { |u| u.has_role?(:bank_supervisor) && !u.has_role?(:partner_admin) }
        @agents = []
      else
        @agents      = @team_members.select { |u| u.has_role?(:partner_agent) && !u.has_role?(:partner_admin) }
        @supervisors = @team_members.select { |u| u.has_role?(:partner_supervisor) && !u.has_role?(:partner_admin) }
      end
    end

    # === INVITE FORM ===
    # When linked from a verified BonID lookup card (?bonid=ABCDEF), skip the
    # redundant lookup step and jump straight to the confirm/role-assignment view.
    def new
      @role_options = role_options
      return unless params[:bonid].present?

      @bonid = params[:bonid].to_s.strip
      @person = TeamInvitationService.lookup(@bonid)
      return if @person.nil? || !@person[:verified]

      load_electoral_offices_for_cep
      render :confirm
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
      load_electoral_offices_for_cep
      render :confirm
    end

    # === SEND INVITATION ===
    def create
      if (reason = cep_invite_invalid_reason)
        flash[:error] = reason
        return redirect_to new_partner_portal_team_path(bonid: params[:bonid])
      end

      result = TeamInvitationService.call(
        partner:     @partner,
        bonid:       params[:bonid],
        role:        params[:role],
        invited_by:  current_user,
        employee_id: params[:employee_id],
        office_code: resolved_office_code
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
        # Remove all possible partner roles
        all_partner_role_keys.each { |r| @member.remove_role(r) if @member.has_role?(r) }
        @member.update!(partner_id: nil)

        PartnerAuditLog.create!(
          partner:    @partner,
          event:      "team_member_revoked",
          details: {
            revoked_email: @member.email,
            revoked_name:  @member.full_name,
            revoked_by:    current_user.full_name,
            revoked_by_id: current_user.id,
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

    # === SUSPEND MEMBER ===
    def suspend
      if @member == current_user
        flash[:error] = "Ou pa ka sispann tèt ou."
        return redirect_to partner_portal_team_index_path
      end

      # Supervisors can only suspend agents/tellers, not admins
      if supervisor_only? && @member.has_role?(:partner_admin)
        flash[:error] = "Sèlman administratè ka sispann yon lòt administratè."
        return redirect_to partner_portal_team_index_path
      end

      unless @member.active?
        flash[:warning] = "#{@member.full_name} deja sispann."
        return redirect_to partner_portal_team_index_path
      end

      ActiveRecord::Base.transaction do
        @member.update!(active: false)

        PartnerAuditLog.create!(
          partner:    @partner,
          event:      "team_member_suspended",
          details: {
            suspended_email: @member.email,
            suspended_name:  @member.full_name,
            suspended_by:    current_user.full_name,
            suspended_by_id: current_user.id,
            reason:          params[:reason],
            ip:              request.remote_ip
          }
        )

        TeamMailer.suspended(
          user:    @member,
          partner: @partner,
          reason:  params[:reason]
        ).deliver_later
      end

      flash[:success] = "#{@member.full_name} sispann."
      redirect_to partner_portal_team_index_path
    end

    # === REACTIVATE MEMBER ===
    def reactivate
      if supervisor_only? && @member.has_role?(:partner_admin)
        flash[:error] = "Sèlman administratè ka reaktive yon lòt administratè."
        return redirect_to partner_portal_team_index_path
      end

      if @member.active?
        flash[:warning] = "#{@member.full_name} deja aktif."
        return redirect_to partner_portal_team_index_path
      end

      ActiveRecord::Base.transaction do
        @member.update!(active: true)

        PartnerAuditLog.create!(
          partner:    @partner,
          event:      "team_member_reactivated",
          details: {
            reactivated_email: @member.email,
            reactivated_name:  @member.full_name,
            reactivated_by:    current_user.full_name,
            reactivated_by_id: current_user.id,
            ip:                request.remote_ip
          }
        )

        TeamMailer.reactivated(
          user:    @member,
          partner: @partner
        ).deliver_later
      end

      flash[:success] = "#{@member.full_name} reaktive."
      redirect_to partner_portal_team_index_path
    end

    # === REASSIGN ROLE ===
    def update_role
      if @member == current_user
        flash[:error] = "Ou pa ka chanje wòl tèt ou."
        return redirect_to partner_portal_team_index_path
      end

      new_role = params[:role].to_s
      sector = partner_sector_key
      valid_keys = GovernmentRoleConstants.valid_role_keys_for(sector)

      unless valid_keys.include?(new_role)
        flash[:error] = "Wòl \"#{new_role}\" pa valid pou sektè sa a."
        return redirect_to partner_portal_team_index_path
      end

      old_roles = all_partner_role_keys.select { |r| @member.has_role?(r) }

      ActiveRecord::Base.transaction do
        # Remove all existing partner roles
        all_partner_role_keys.each { |r| @member.remove_role(r) if @member.has_role?(r) }

        # Assign new role
        @member.add_role(new_role)

        new_label = GovernmentRoleConstants.role_label(sector, new_role)

        PartnerAuditLog.create!(
          partner:    @partner,
          event:      "team_member_role_changed",
          details: {
            member_email:  @member.email,
            member_name:   @member.full_name,
            old_roles:     old_roles,
            new_role:      new_role,
            new_role_label: new_label,
            changed_by:    current_user.full_name,
            ip:            request.remote_ip
          }
        )
      end

      new_label = GovernmentRoleConstants.role_label(sector, new_role)
      flash[:success] = "#{@member.full_name} se #{new_label} kounye a."
      redirect_to partner_portal_team_index_path
    end

    private

    # Alias so controller + views can use current_user consistently
    def current_user
      current_portal_user
    end
    helper_method :current_user

    def set_partner_alias
      @partner = @current_partner
    end

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

    # ============================================================
    # AUTHORIZATION
    # ============================================================
    def require_admin!
      return if current_user.has_role?(:partner_admin)

      flash[:error] = "Sèlman administratè ka fè aksyon sa a."
      redirect_to partner_portal_team_index_path
    end

    def require_admin_or_supervisor!
      return if current_user.has_role?(:partner_admin)
      return if current_user.has_role?(:partner_supervisor)
      return if current_user.has_role?(:bank_supervisor)

      flash[:error] = "Sèlman administratè oswa sipèvizè ka fè aksyon sa a."
      redirect_to partner_portal_team_index_path
    end

    # True when user is a supervisor but NOT an admin
    def supervisor_only?
      !current_user.has_role?(:partner_admin) &&
        (current_user.has_role?(:partner_supervisor) || current_user.has_role?(:bank_supervisor))
    end

    # ============================================================
    # SECTOR HELPERS
    # ============================================================
    def partner_sector_key
      (@partner.department_sector || @partner.sector).to_s.downcase
    end

    def onaca_sector?
      partner_sector_key == "onaca"
    end

    def banking_sector?
      GovernmentRoleConstants::BANKING_SECTORS.include?(partner_sector_key)
    end

    def cep_sector?
      partner_sector_key == "cep"
    end

    # CEP v1 assignments map cleanly onto the org chart:
    #   - partner_admin  = 1 of 9 CEP commissioners → CEP HQ (no biwo picker)
    #   - partner_agent  = field enrollment officer → must pick a BEK
    # BEDs are intentionally excluded — the BED-level institutional roles
    # (regional coordinators/supervisors) were dropped in the v1 role trim,
    # so no v1 invitee is ever assigned to a BED.
    def load_electoral_offices_for_cep
      return unless cep_sector?
      @beks = ElectoralOffice.bek.where(status: %w[open planned]).ordered
    end

    # Force the biwo to match the role:
    #   - partner_admin → always "CEP HQ — Port-au-Prince" (commissioner seat)
    #   - partner_agent → posted BEK id resolved to display_label
    # Other sectors pass their raw free-text office_code through unchanged.
    def resolved_office_code
      return params[:office_code].to_s.strip unless cep_sector?

      case params[:role].to_s
      when "partner_admin"
        "CEP HQ — Port-au-Prince"
      when "partner_agent"
        raw = params[:office_code].to_s.strip
        return nil if raw.blank?
        bek = ElectoralOffice.bek.find_by(id: raw)
        bek&.display_label
      end
    end

    # Reject CEP invites whose role/biwo combo is structurally invalid before
    # we hit the service. The service treats office_code as a free string, so
    # this is the only place that enforces the org chart.
    def cep_invite_invalid_reason
      return nil unless cep_sector?
      role = params[:role].to_s
      raw  = params[:office_code].to_s.strip

      case role
      when "partner_admin"
        nil # office_code is ignored for admins; nothing to validate
      when "partner_agent"
        return "Chwazi yon BEK pou Ajan Enskripsyon an." if raw.blank?
        return "BEK chwazi a pa egziste." unless ElectoralOffice.bek.exists?(id: raw)
        nil
      else
        "Wòl pa valid pou yon envitasyon CEP."
      end
    end

    ALL_PARTNER_ROLES = %i[
      partner_admin partner_agent partner_agent_surveyor partner_agent_notary partner_supervisor
      bank_agent bank_teller bank_supervisor
    ].freeze

    def all_partner_role_keys
      ALL_PARTNER_ROLES
    end

    helper_method :onaca_sector?, :banking_sector?, :cep_sector?
  end
end
