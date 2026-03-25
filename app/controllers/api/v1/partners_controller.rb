# frozen_string_literal: true

module Api
  module V1
    class PartnersController < Api::V1::BaseController
      before_action :authenticate_api_key!

      # --------------------------------------------------------------------------
      # GET /api/v1/partner/metrics
      # Returns usage metrics for the authenticated partner
      # --------------------------------------------------------------------------
      def metrics
        start_time = 24.hours.ago
        logs = ApiAccessLog.where(partner_id: @current_partner.id)
                           .where("created_at >= ?", start_time)

        total   = logs.count
        success = logs.where(success: true).count
        failed  = total - success
        avg_latency = logs.average(:duration_ms)&.round(2)

        endpoint_breakdown = logs.group(:endpoint).count.map do |endpoint, count|
          { endpoint: endpoint, requests: count }
        end

        render json: {
          partner: {
            id: @current_partner.id,
            name: @current_partner.name,
            sector: @current_partner.sector
          },
          period: "last_24h",
          metrics: {
            total_requests: total,
            successful_requests: success,
            failed_requests: failed,
            avg_latency_ms: avg_latency
          },
          endpoint_breakdown: endpoint_breakdown,
          rate_limit: {
            limit: 1000,
            remaining: (1000 - total)
          },
          generated_at: Time.current.iso8601
        }, status: :ok

      rescue => e
        Rails.logger.error("[API::PartnerMetricsError] #{e.class}: #{e.message}")
        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      end

      private

      # --------------------------------------------------------------------------
      # Authenticate using X-Partner-Api-Key header
      # --------------------------------------------------------------------------
      def authenticate_api_key!
        header_key = request.headers["X-Partner-Api-Key"].to_s.strip
        return render json: { error: "Missing API key" }, status: :unauthorized if header_key.blank?

        digest = Digest::SHA256.hexdigest(header_key)
        @current_partner = ::Partner.find_by(api_key_digest: digest) # ✅ explicit top-level reference

        unless @current_partner&.verified_at.present?
          render json: { error: "Invalid or inactive API key" }, status: :unauthorized
        end
      rescue => e
        Rails.logger.error("[API::AuthError] #{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
        render json: { error: "Internal authentication error" }, status: :internal_server_error
      end
    end
  end
end
