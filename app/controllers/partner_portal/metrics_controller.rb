# frozen_string_literal: true

module PartnerPortal
  class MetricsController < PartnerPortal::BaseController
    before_action :set_partner

    def show
      metrics_data = PartnerMetricsService.new(@partner).call

      render json: metrics_data, status: :ok
    rescue => e
      Rails.logger.error("MetricsController error: #{e.message}")
      render json: { error: "Unable to load metrics" }, status: :internal_server_error
    end

    private

    def set_partner
      @partner = current_partner_admin&.partner ||
                 current_partner ||
                 Partner.find_by(slug: params[:partner])
      head :unauthorized unless @partner
    end
  end
end
