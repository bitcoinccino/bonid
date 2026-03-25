module Admin
  class OfficersController < Admin::ApplicationController
    before_action :set_partner

    def new
      @officer = Officer.new
    end

    def create
      email = officer_params[:email].downcase.strip
      existing_user = User.find_by(email: email)

      if existing_user&.officer
        officer = existing_user.officer

        if officer.invitation_accepted_at.present?
          redirect_to admin_officers_path, alert: "⚠️ Officer with email #{email} is already onboarded."
          return
        else
          # Resend invitation with fresh token
          existing_user.invitation_token = nil
          existing_user.invite!(skip_invitation: true)
          raw_token = existing_user.raw_invitation_token

          OfficerInviteMailer.single_invite(
            email,
            officer_invite_url(officer, invitation_token: raw_token),
            officer.partner&.name || "your agency"
          ).deliver_later

          redirect_to admin_officers_path, notice: "📧 Officer already invited. Token refreshed and invitation re-sent to #{email}."
          return
        end
      end

      # Create or re-invite user
      user = if existing_user
               existing_user.invite!(skip_invitation: true)
      else
               User.invite!({ email: email }, curren_admin_user) { |u| u.skip_invitation = true }
      end
      raw_token = user.raw_invitation_token

      # Build officer record
      @officer = Officer.new(officer_params.except(:email))
      @officer.email   = email
      @officer.partner = @partner
      @officer.user    = user

      if @officer.save
        OfficerInviteMailer.single_invite(
          email,
          officer_invite_url(@officer, invitation_token: raw_token),
          @partner.name
        ).deliver_later

        redirect_to admin_officers_path, notice: "✅ Officer invitation sent to #{email}."
      else
        flash.now[:alert] = "🚫 Failed to send invitation. Please correct the form below."
        render :new, status: :unprocessable_entity
      end
    end

    private

    def set_partner
      @partner = curren_admin_user.partner || Partner.find(params[:partner_id])
    end

    def officer_params
      params.require(:officer).permit(:email, :first_name, :last_name, :rank, :unit_name, :unit_type)
    end
  end
end
