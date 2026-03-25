# frozen_string_literal: true

class Rack::Attack
  throttle("qr_scans/ip", limit: 300, period: 60.seconds) do |req|
    req.ip if req.path.start_with?("/verify") || req.path.start_with?("/bonid_lookup")
  end

  throttle("api/requests_by_api_key", limit: 1000, period: 1.minute) do |req|
    next unless req.path.start_with?("/api/v1")
    req.get_header("HTTP_X_PARTNER_API_KEY") || req.get_header("HTTP_X_API_KEY")
  end

  # Liveness sessions are expensive AWS calls — tighter per-IP limit
  throttle("liveness/ip", limit: 20, period: 60.seconds) do |req|
    req.ip if req.path.include?("liveness_session")
  end

  # Passport OCR — expensive AWS Textract calls
  throttle("passport_ocr/ip", limit: 10, period: 60.seconds) do |req|
    req.ip if req.path.include?("scan_passport")
  end

  # Visitor liveness — same limit as citizen liveness
  throttle("visitor_liveness/ip", limit: 20, period: 60.seconds) do |req|
    req.ip if req.path.include?("visitors") && (req.path.include?("liveness") || req.path.include?("face_compare"))
  end

  safelist("allow from localhost") { |req| [ "127.0.0.1", "::1" ].include?(req.ip) }
end

# Logging hook (unchanged)
ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, start, finish, _id, payload|
  req = payload[:request]
  next unless req.respond_to?(:get_header)
  next unless req.path.start_with?("/api/v1")

  api_key = req.get_header("HTTP_X_PARTNER_API_KEY") || req.get_header("HTTP_X_API_KEY")
  next unless api_key.present?

  begin
    partner = Partner.find_by(api_key_digest: Digest::SHA256.hexdigest(api_key))
    next unless partner&.active?

    duration = ((finish - start) * 1000).round(2)
    limit = 1000
    cache_key = "rack::attack:#{api_key}"
    match_data = Rack::Attack.cache.store.read(cache_key)
    count = match_data&.dig(:count) || 0
    remaining = [ limit - count, 0 ].max

    ApiAccessLog.create!(
      partner: partner,
      endpoint: req.path,
      ip_address: req.ip,
      success: payload[:status].to_i < 500,
      status: payload[:status].to_s,
      response_message: Rack::Utils::HTTP_STATUS_CODES[payload[:status].to_i] || "Unknown",
      duration_ms: duration,
      metadata: {
        controller: payload[:controller],
        action: payload[:action],
        params: (payload[:params] || {}).except("controller", "action"),
        duration_ms: duration,
        requests_remaining: remaining,
        limit: limit,
        ip: req.ip,
        timestamp: Time.current
      }
    )
  rescue => e
    Rails.logger.error("[Rack::Attack] ⚠️ Logging failed: #{e.class} — #{e.message}")
  end
end

# Custom throttle response
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"]
  retry_after = match_data&.[](:period) ? match_data[:period] - (Time.now.utc.to_i % match_data[:period]) : 60

  [
    429,
    { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
    [ {
      error: "Too many requests",
      retry_after: "#{retry_after} seconds"
    }.to_json ]
  ]
end

# # === BonID API middlewares ===
# Rails.application.config.middleware.insert_after Rack::Attack, Middleware::ApiKeyAuth
# Rails.application.config.middleware.insert_after Middleware::ApiKeyAuth, Middleware::ConditionalApiKeyAuth
