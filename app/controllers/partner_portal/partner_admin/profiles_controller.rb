# frozen_string_literal: true

module PartnerPortal
  module PartnerAdmin
    class ProfilesController < PartnerPortal::BaseController
      def edit
        @partner = @current_partner
      end

      def update
        @partner = @current_partner

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
          :contact_person,
          :phone_number,
          :email,
          :website,
          :description,
          :logo,
          :unit_type,
          :unit_name,
          :department_sector,
          address_attributes: [
            :id, :street_address, :locality, :postal_code,
            :department_id, :arrondissement_id, :commune_id,
            :communal_section_id, :country
          ]
        )
      end
    end
  end
end
