# frozen_string_literal: true

module PartnerPortal
  module PartnerAdmins
    # Handles registration attempts for Partner Admins.
    # Registration is disabled — Partner Admins must be invited by BonID system administrators.
    class RegistrationsController < Devise::RegistrationsController
      layout "partner_admin_auth"

      before_action :load_partner_from_invite_token, only: %i[new create]

      # GET /partner_admins/sign_up
      # Block open registration — Partner Admins must be invited
      def new
        flash[:alert] = "Partner Admins must be invited by BonID system administrators."
        redirect_to new_partner_admin_session_path
      end

      # POST /partner_admins
      # For internal admin use — invites a new partner admin via Devise Invitable
      def create
        @partner_admin = User.invite!(
          email: params[:user][:email],
          partner: @partner
        )

        @partner_admin.add_role(:partner_admin)

        if @partner_admin.persisted?
          flash[:notice] = "✅ Invitation sent to #{@partner_admin.email}"
          redirect_to PartnerPortalRouter.dashboard_path_for(current_partner_admin)
        else
          flash.now[:alert] = "⚠️ Failed to send invitation."
          render :new, status: :unprocessable_entity
        end
      rescue StandardError => e
        Rails.logger.error("[PartnerAdmin::RegistrationsController] Invitation failed: #{e.class} - #{e.message}")
        flash.now[:alert] = "❌ An error occurred while inviting the partner admin."
        render :new, status: :unprocessable_entity
      end

      # PATCH/PUT /partner_admins
      def update
        super do |resource|
          resource.add_role(:partner_admin) unless resource.has_role?(:partner_admin)
          resource.partner ||= @partner
        end
      end

      protected

      def after_sign_up_path_for(resource)
        ::PartnerPortalRouter.dashboard_path_for(resource)
      end

      def after_update_path_for(resource)
        ::PartnerPortalRouter.dashboard_path_for(resource)
      end

      private

      def load_partner_from_invite_token
        @partner = Partner.find_by(id: params[:partner_id]) if params[:partner_id].present?
      end

      def sign_up_params
        params.require(:user).permit(:email, :password, :password_confirmation)
      end

      def account_update_params
        params.require(:user).permit(:email, :password, :password_confirmation, :current_password)
      end
    end
  end
end
