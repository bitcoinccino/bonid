# frozen_string_literal: true

module RateLimitable
  extend ActiveSupport::Concern

  included do
    before_action :apply_rate_limit_headers
  end

  private

  def apply_rate_limit_headers
    # Use @partner (set by BaseController auth) or @current_partner
    partner = @partner || @current_partner
    return unless partner

    # Credit-balance-based rate limits
    limit = credit_based_rate_limit(partner)
    timeframe = 1.minute

    cache_key    = "partner:#{partner.id}:api_hits:min"
    current_hits = Rails.cache.read(cache_key).to_i

    # Check if rate limited
    if current_hits >= limit
      reset_at = (Time.now + timeframe).utc.iso8601
      response.set_header("X-RateLimit-Limit", limit)
      response.set_header("X-RateLimit-Remaining", 0)
      response.set_header("X-RateLimit-Reset", reset_at)
      response.set_header("Retry-After", timeframe.to_i.to_s)

      payload = {
        status: "too_many_requests",
        error: "Rate limit exceeded",
        message: "Ou depase limit API a (#{limit}/min). Rechaje kredi ou pou plis kapasite.",
        limit: limit,
        reset_at: reset_at,
        top_up_url: "/partner_portal/credits",
        timestamp: Time.current.iso8601
      }
      sign_response(payload) if respond_to?(:sign_response, true)
      render json: payload, status: :too_many_requests
      return
    end

    # Increment usage
    Rails.cache.write(cache_key, current_hits + 1, expires_in: timeframe)

    remaining = [limit - (current_hits + 1), 0].max
    reset_at  = (Time.now + timeframe).utc.iso8601

    response.set_header("X-RateLimit-Limit", limit)
    response.set_header("X-RateLimit-Remaining", remaining)
    response.set_header("X-RateLimit-Reset", reset_at)
    response.set_header("X-BonID-Partner", partner.slug)

    # Log every 25th request for metrics
    if (current_hits % 25).zero?
      ApiAccessLog.create!(
        partner: partner,
        endpoint: request.path,
        ip_address: request.remote_ip,
        success: true,
        metadata: {
          rate_limit: { limit: limit, remaining: remaining, reset_at: reset_at },
          user_agent: request.user_agent,
          timestamp: Time.current
        }.to_json
      )
    end
  rescue => e
    Rails.logger.warn("[RateLimitable] #{e.class}: #{e.message}")
  end

  # Credit-balance-based rate limits
  # Higher credit balance = more API capacity
  def credit_based_rate_limit(partner)
    balance = partner.credit_balance
    case
    when balance >= 100 then 5000   # $100+
    when balance >= 50  then 1000   # $50+
    when balance >= 10  then 500    # $10+
    when balance >= 1   then 100    # $1+
    else 20
    end
  end
end
