# frozen_string_literal: true

# PartnerPortal::TeamInvitationsController
# =========================================
# Handles the acceptance side of team invitations.
# When a user clicks "Aksepte Envitasyon" in the email, they land here.
#
# Flow:
#   1. User clicks link with ?invitation_token=xxx
#   2. GET  /team/invitation/accept → show acceptance page
#   3. PUT  /team/invitation/accept → accept invitation, set password if needed
#   4. Redirect to partner portal dashboard

class PartnerPortal::TeamInvitationsController < ApplicationController
  before_action :find_user_by_token

  # GET /team/invitation/accept?invitation_token=xxx
  def show
    # Render acceptance form (password setup if needed)
  end

  # PUT /team/invitation/accept
  def update
    submitted_password = params.dig(:user, :password)
    if @user.encrypted_password.blank? || submitted_password.present?
      unless @user.update(password_params)
        flash[:error] = @user.errors.full_messages.join(", ")
        return render :show
      end
    end

    @user.update!(invitation_accepted_at: Time.current)

    # Sign them in
    sign_in(:user, @user)

    # Audit — route through log! so plain-User invitees (unified BonID
    # invite path → rolify, no STI promotion) don't trip the admin_user
    # AssociationTypeMismatch. The factory guards is_a?(AdminUser).
    PartnerAuditLog.log!(
      @user.partner,
      @user,
      "team_invitation_accepted",
      email: @user.email,
      name:  @user.full_name,
      ip:    request.remote_ip
    )

    flash[:success] = "Byenveni nan ekip #{@user.partner&.name}!"
    redirect_to after_accept_path
  end

  private

  def find_user_by_token
    token = params[:invitation_token]
    return redirect_with_error unless token.present?

    # Devise stores a digested version of the token
    digested = Devise.token_generator.digest(User, :invitation_token, token)
    @user = User.find_by(invitation_token: digested)

    return redirect_with_error unless @user
    @raw_token = token
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

  def redirect_with_error
    flash[:error] = "Lyen envitasyon an pa valid oswa li ekspire. Mande administratè ou voye yon nouvo envitasyon."
    redirect_to root_path
  end

  def after_accept_path
    sector = @user.partner&.department_sector || @user.partner&.sector
    case sector&.downcase
    when "pnh", "law_enforcement"
      partner_portal_law_enforcement_dashboard_path
    else
      partner_portal_dashboard_path
    end
  rescue
    root_path
  end
end
