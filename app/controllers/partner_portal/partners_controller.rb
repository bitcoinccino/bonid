# frozen_string_literal: true

module PartnerPortal
  class PartnersController < PartnerPortal::BaseController
    layout "partner_portal/public" # or your default layout

    def new
      @partner = Partner.new
    end

    def create
      @partner = Partner.new(partner_params)

      if @partner.save
        redirect_to partner_portal_success_path, notice: "✅ Partner application submitted successfully."
      else
        flash.now[:alert] = "⚠️ Please correct the highlighted errors."
        render :new, status: :unprocessable_entity
      end
    end

    private

    def partner_params
      params.require(:partner).permit(
        :name,
        :email,
        :phone_number,
        :sector,
        :unit_type,
        :unit_name
      )
    end
  end
end
