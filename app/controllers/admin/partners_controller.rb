# app/controllers/admin/partners_controller.rb
module Admin
  class PartnersController < Admin::ApplicationController
    before_action :set_partner, only: [:show, :edit, :update, :destroy]
    def index
      @partners = Partner.order(created_at: :desc)
    end


    def show
      @partner = Partner.find_by(id: params[:id])
      unless @partner
        redirect_to admin_partners_path, alert: "Partner not found." and return
        end
    end


    def edit
      @partner = Partner.find(params[:id])
      @partner.build_address if @partner.address.blank?
    end

    def update
      if @partner.update(partner_params)
        if @partner.address.present? && address_params.present?
          @partner.address.update(address_params)
          @partner.address.geocode
          @partner.address.save!
        end

        if params[:partner][:logo].present?
          @partner.logo.attach(params[:partner][:logo])
        end

        redirect_to admin_partner_path(@partner), notice: "✅ Partner updated successfully."
      else
        flash.now[:alert] = "⚠️ Please fix the errors below."
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_partner
      @partner = Partner.find(params[:id])
    end

    def partner_params
      params.require(:partner).permit(
        :name,
        :sector,
        :description,
        :website,
        :verified_at,
        :email,
        :phone_number
      )
    end

    def address_params
      params.require(:partner).require(:address_attributes).permit(
        :department_id,
        :arrondissement_id,
        :commune_id,
        :communal_section_id,
        :postal_code,
        :street_address,
        :locality,
        :country
      )
    end
  end

  # Resend verification email to the partner
  def resend_verification_email
    partner = Partner.find(params[:id])
    PartnerMailer.approved(partner).deliver_later
    redirect_to admin_partners_path, notice: "Verification email resent to #{partner.name}."
  end
end
