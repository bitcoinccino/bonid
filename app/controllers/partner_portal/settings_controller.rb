# frozen_string_literal: true

module PartnerPortal
  class SettingsController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!

    # GET /partner_portal/settings
    def index
      @partner = @current_partner
    end

    # PATCH /partner_portal/settings/:id
    def update
      @partner = @current_partner

      if @partner.update(settings_params)
        redirect_to partner_portal_settings_path, notice: "Settings updated successfully."
      else
        flash.now[:alert] = "Failed to update settings."
        render :index, status: :unprocessable_entity
      end
    end

    private

    def settings_params
      params.require(:partner).permit(
        :contact_person, :phone_number, :website, :webhook_url
      )
    end
  end
end
