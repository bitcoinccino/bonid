# frozen_string_literal: true

class PartnerMetricsService
  def initialize(partner)
    @partner = partner
  end

  def call
    logs = ApiAccessLog.where(partner: @partner).where("created_at >= ?", 24.hours.ago)

    {
      partner: {
        id: @partner.id,
        name: @partner.name,
        sector: @partner.sector
      },
      period: "last_24h",
      metrics: {
        total_requests: logs.count,
        successful_requests: logs.where(status_code: 200).count,
        failed_requests: logs.where("status_code >= 400").count,
        avg_latency_ms: logs.average(:latency_ms)&.round(2),
        daily_quota: 10_000
      },
      endpoint_breakdown: logs.group(:endpoint).count.map { |endpoint, count| { endpoint:, requests: count } },
      rate_limit: {
        limit: 10_000,
        remaining: [ 10_000 - logs.count, 0 ].max
      },
      generated_at: Time.current
    }
  end
end
