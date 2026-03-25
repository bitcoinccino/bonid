
module Admin
  class PartnerAdminInvitationsController < BaseController
    layout "partner_admin_auth"
    def new
      @partner = Partner.find(params[:partner_id])
    end

    def create
      @partner = Partner.find(params[:partner_id])
      user = User.find_or_initialize_by(email: params[:email])

      if user.persisted?
        token = generate_reset_password_token(user) # ✅ silent token generation
      else
        user = User.invite!(email: params[:email], invited_by: current_admin_user)
        token = user.invitation_token
      end

      # ✅ Only our branded mailer fires
      Partners::AdminMailer.invite(user: user, token: token, partner: @partner).deliver_later

      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = "Invitation sent to #{user.email}"
          render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
        end
        format.html { redirect_to admin_partner_path(@partner), notice: "Invitation sent." }
      end
    rescue => e
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "🚨 Invite failed: #{e.message}"
          render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash")
        end
        format.html { redirect_to admin_partner_path(@partner), alert: "Invite failed: #{e.message}" }
      end
    end

    private

    # 🔒 generate token without emailing
    def generate_reset_password_token(user)
      raw, enc = Devise.token_generator.generate(User, :reset_password_token)
      user.update!(
        reset_password_token: enc,
        reset_password_sent_at: Time.current
      )
      raw
    end
  end
end
