
# app/controllers/admin/officers_controller.rb
module Admin
  class OfficersController < Admin::ApplicationController
    before_action :set_partner

    def index
      @officers = @partner.officers.order(created_at: :desc)
    end

    def new
      @officer = @partner.officers.build
    end

    def create
      @officer = @partner.officers.build(officer_params)
      if @officer.save
        OfficerMailer.invitation(@officer).deliver_later
        redirect_to admin_partner_path(@partner), notice: "Officer invited successfully."
      else
        render :new
      end
    end

    private

    def set_partner
      @partner = Partner.find(params[:partner_id])
    end

    def officer_params
      params.require(:officer).permit(:full_name, :badge_id, :rank, :unit_name, :unit_type, :email, :phone_number)
    end
  end
end
