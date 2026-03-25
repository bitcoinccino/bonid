# app/controllers/partner_portal/analytics_controller.rb
module PartnerPortal
  class AnalyticsController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!
    before_action :set_partner

    def index
      @total_requests   = @partner.api_access_logs.count
      @successful_calls = @partner.api_access_logs.where(success: true).count
      @throttled_calls  = @partner.api_access_logs.where(success: false).count

      # Grouped data for charts
      @calls_by_endpoint = @partner.api_access_logs
        .group(:endpoint)
        .count
        .sort_by { |_endpoint, count| -count }
        .to_h

      @calls_by_day = @partner.api_access_logs
        .where("created_at >= ?", 14.days.ago)
        .group("DATE(created_at)")
        .order("DATE(created_at)")
        .count

      respond_to do |format|
        format.html
        format.json { render json: analytics_json }
      end
    end

    private

    def set_partner
      @partner = current_partner_admin.partner
    end

    def analytics_json
      {
        total_requests: @total_requests,
        successful_calls: @successful_calls,
        throttled_calls: @throttled_calls,
        calls_by_endpoint: @calls_by_endpoint,
        calls_by_day: @calls_by_day
      }
    end
  end
end
