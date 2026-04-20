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
#
# Content-aware: API and JSON-fetch clients (XHR, /api/, Accept: json)
# get a structured JSON 429. Browser form posts get an HTML 429 page so a
# citizen submitting a form sees a friendly Kreyòl message + back link
# instead of a raw JSON blob.
Rack::Attack.throttled_responder = lambda do |request|
  match_data  = request.env["rack.attack.match_data"]
  retry_after = match_data&.[](:period) ? match_data[:period] - (Time.now.utc.to_i % match_data[:period]) : 60

  accept       = request.get_header("HTTP_ACCEPT").to_s
  xhr          = request.get_header("HTTP_X_REQUESTED_WITH").to_s.downcase == "xmlhttprequest"
  api_path     = request.path.start_with?("/api/")
  wants_json   = api_path || xhr || accept.include?("application/json")

  if wants_json
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [ {
        error: "Too many requests",
        retry_after: "#{retry_after} seconds"
      }.to_json ]
    ]
  else
    minutes = (retry_after.to_f / 60).ceil
    wait_label = minutes <= 1 ? "yon minit" : "#{minutes} minit"
    body = <<~HTML
      <!DOCTYPE html>
      <html lang="ht">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Twòp esèy — BonID</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
                 background: #F8FAFC; color: #1E293B; margin: 0; padding: 2rem 1rem;
                 display: flex; align-items: center; justify-content: center; min-height: 100vh; }
          .card { background: #fff; border: 1px solid #E2E8F0; border-radius: 1rem;
                  padding: 2rem; max-width: 28rem; width: 100%; text-align: center;
                  box-shadow: 0 4px 20px rgba(15, 23, 42, 0.06); }
          .icon { width: 3.5rem; height: 3.5rem; border-radius: 999px; background: #FEF3C7;
                  color: #B45309; display: inline-flex; align-items: center; justify-content: center;
                  font-size: 1.6rem; margin-bottom: 1rem; }
          h1 { font-size: 1.15rem; margin: 0 0 0.5rem; color: #0F172A; }
          p  { color: #475569; font-size: 0.92rem; line-height: 1.5; margin: 0 0 1.25rem; }
          .btn { display: inline-block; background: #00209F; color: #fff; padding: 0.6rem 1.1rem;
                 border-radius: 999px; text-decoration: none; font-weight: 600; font-size: 0.88rem; }
          .btn:hover { background: #001570; }
          .meta { display: block; color: #94A3B8; font-size: 0.78rem; margin-top: 1rem; }
        </style>
      </head>
      <body>
        <div class="card" role="alert">
          <div class="icon">⏱</div>
          <h1>Twòp esèy — tann yon ti moman</h1>
          <p>
            Nou resevwa twòp demann nan tan kout. Tanpri tann
            <strong>#{wait_label}</strong> epi eseye ankò.
          </p>
          <a class="btn" href="javascript:history.back()">Retounen</a>
          <span class="meta">Erè 429 · Retry-After #{retry_after}s</span>
        </div>
      </body>
      </html>
    HTML

    [
      429,
      {
        "Content-Type" => "text/html; charset=utf-8",
        "Retry-After"  => retry_after.to_s,
        "Cache-Control" => "no-store"
      },
      [body]
    ]
  end
end

# # === BonID API middlewares ===
# Rails.application.config.middleware.insert_after Rack::Attack, Middleware::ApiKeyAuth
# Rails.application.config.middleware.insert_after Middleware::ApiKeyAuth, Middleware::ConditionalApiKeyAuth
