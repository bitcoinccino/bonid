class PartnerPortal::OfficerInvitationsController < PartnerPortal::BaseController
  before_action :authenticate_partner_admin!
  before_action :set_partner

  def new
    @officer = User.new
  end

  def create
    email = officer_params[:email].strip.downcase
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
      existing.update!(partner_id: @partner.id) unless existing.partner_id == @partner.id

      raw_token, digested_token = Devise.token_generator.generate(User, :invitation_token)
      existing.update!(
        invitation_token:      digested_token,
        invitation_created_at: Time.current,
        invitation_sent_at:    Time.current
      )

      Officers::OfficerMailer.invitation_email(existing, raw_token).deliver_later

      AuditLog.create!(
        user: current_user,
        action: "resend_officer_invitation",
        description: "Resent invitation to officer #{existing.email} (BonID verified) for partner #{@partner.name} (ID: #{@partner.id})"
      )

      flash[:success] = "Invitation sent to verified officer #{existing.full_name || existing.email}."
      return redirect_to partner_portal_law_enforcement_dashboard_path
    end

    # ============================================================
    # NEW USER: Cannot invite someone without existing BonID
    # They must first register as a citizen and get BonID approved
    # ============================================================
    flash[:error] = "No citizen found with this email. The person must first register on BonID and have their identity verified before they can be invited as an officer."
    redirect_to partner_portal_law_enforcement_officers_path
  end

  private

  def set_partner
    @partner = @current_partner
    return if @partner.present?

    redirect_to partner_portal_root_path, alert: "Partner not found."
  end

  def officer_params
    params.require(:user).permit(:first_name, :last_name, :email, :phone_number, :rank, :badge_number)
  end
end
