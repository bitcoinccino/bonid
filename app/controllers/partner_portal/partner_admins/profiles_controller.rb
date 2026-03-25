module PartnerPortal
  module PartnerAdmins
    class ProfilesController < ApplicationController
      before_action :authenticate_partner_admin!  # Devise helper for partner_admin

      def show
        @partner = current_partner_admin.partner
      end

      def edit
        @partner = current_partner_admin.partner
      end

      def update
        @partner = current_partner_admin.partner
        if @partner.update(partner_params)
          redirect_to PartnerPortalRouter.dashboard_path_for(current_partner_admin),
             notice: "Your profile has been updated successfully."

        else
          flash.now[:alert] = "Please correct the errors below."
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def partner_params
        params.require(:partner).permit(
          :name,
          :email,
          :phone,
          :sector,
          :department,
          :plan,
          :estimated_team_size,
          :intended_users_to_verify,
          :preferred_integration,
          :how_did_you_hear,
          :compliance_cert_upload
        )
      end
    end
  end
end
