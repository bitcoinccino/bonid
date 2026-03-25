# frozen_string_literal: true

module PartnerPortal
  module PartnerAdmins
    # Handles confirmation of partner-admin accounts (Devise Confirmable).
    class ConfirmationsController < Devise::ConfirmationsController
      layout "partner_admin_auth"

      # GET /partner_admins/confirmation?confirmation_token=abcdef
      def show
        self.resource = resource_class.confirm_by_token(params[:confirmation_token])

        if resource.errors.empty?
          flash[:notice] = "✅ Your email has been confirmed successfully."
          redirect_to ::PartnerPortalRouter.dashboard_path_for(resource)

        else
          flash[:alert] = "⚠️ Invalid or expired confirmation link."
          redirect_to new_partner_admin_session_path
        end
      end

      # POST /partner_admins/confirmation
      def create
        self.resource = resource_class.send_confirmation_instructions(resource_params)

        if successfully_sent?(resource)
          flash[:notice] = "📩 Confirmation instructions have been sent to your email."
          redirect_to new_partner_admin_session_path
        else
          flash.now[:alert] = "⚠️ Unable to send confirmation instructions."
          render :new, status: :unprocessable_entity
        end
      end

      private

      def after_resending_confirmation_instructions_path_for(_resource_name)
        new_partner_admin_session_path
      end

      def after_confirmation_path_for(resource_name, resource)
        ::PartnerPortalRouter.dashboard_path_for(resource)
      end
    end
  end
end
