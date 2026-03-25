# app/controllers/partner_portal/partner_admin/dashboard_controller.rb
module PartnerPortal
  module PartnerAdmins
    class DashboardController < PartnerPortal::BaseController
      before_action :authenticate_partner_admin!

      # 🧭 Redirect partner admins to their sector-specific dashboard
      def index
        partner = current_partner_admin&.partner

        unless partner
          redirect_to partner_portal_dashboard_path, alert: "Partner not found."
          return
        end

        case partner.sector
        when "banking"
          redirect_to partner_portal_banking_dashboard_path
        when "embassy"
          redirect_to partner_portal_embassy_dashboard_path
        when "hospital"
          redirect_to partner_portal_hospital_dashboard_path
        when "law_enforcement"
          redirect_to partner_portal_law_enforcement_dashboard_path
        else
          redirect_to partner_portal_dashboard_path, alert: "Unknown sector type."
        end
      end
    end
  end
end
