# frozen_string_literal: true

module PartnerPortal
  class ApiUsageController < PartnerPortal::BaseController
    def index
      # Fetch the latest 200 logs for the current partner (ordered for display)
      @logs = @current_partner.partner_api_logs.order(requested_at: :desc).limit(200)

      # Compute metrics using separate queries to avoid grouping conflicts
      @metrics = {
        total_requests: @logs.count,
        success_rate: rate(@logs, :success),
        # Top 5 endpoints with count and last request time (separate query to avoid ORDER BY in GROUP BY)
        top_endpoints: top_endpoints(@current_partner.partner_api_logs, 5)
      }
    end

    private

    # Calculate success/failure rate
    def rate(logs, type)
      return 0 if logs.count.zero?
      ((logs.where(status: type).count.to_f / logs.count) * 100).round(2)
    end

    # Returns an array of hashes: [{ endpoint, request_count, last_request_at }, ...]
    # Uses a separate query to avoid ORDER BY conflicting with GROUP BY
    def top_endpoints(api_logs_relation, limit = 5)
      api_logs_relation
        .select("endpoint, COUNT(*) AS request_count, MAX(requested_at) AS last_request_at")
        .group(:endpoint)
        .order("request_count DESC")
        .limit(limit)
        .map { |record| {
          endpoint: record.endpoint,
          request_count: record.request_count,
          last_request_at: record.last_request_at
        } }
    end
  end
end
