# app/controllers/partner_portal/access_logs_controller.rb
module PartnerPortal
  class AccessLogsController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!
    before_action :set_partner

    def index
      @logs = PartnerAccessLog.where(partner: @partner)
                              .includes(:admin_user)
                              .order(created_at: :desc)

      # === Filters ===
      if params[:query].present?
        q = "%#{params[:query]}%"
        @logs = @logs.where("action ILIKE :q OR reason ILIKE :q", q: q)
      end

      if params[:actor].present?
        @logs = @logs.joins(:admin_user)
                     .where("users.email ILIKE ?", "%#{params[:actor]}%")
      end

      if params[:date_from].present? && params[:date_to].present?
        @logs = @logs.where(created_at: params[:date_from]..params[:date_to])
      end

      @logs = @logs.limit(100)
    end

    private

    def set_partner
      @partner = current_partner_admin.partner
    end
  end
end
