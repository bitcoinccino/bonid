# frozen_string_literal: true

# config/environments/development.rb
puts ">>> DEVELOPMENT.RB LOADED <<<"

# =======================================================
# FORCE LOCAL STORAGE FIRST — THIS WINS OVER EVERYTHING
# =======================================================
Rails.application.config.active_storage.service = :local

require "active_support/core_ext/integer/time"
require "socket"

Rails.application.configure do
  # =======================================================
  # I18n — STRICT, EXPLICIT, PRODUCTION-SAFE
  # =======================================================
  config.i18n.available_locales = %i[en fr ht]
  config.i18n.default_locale    = :en
  config.i18n.fallbacks = false
  config.i18n.raise_on_missing_translations = true
  config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.yml")]

  # === Core Development Settings ===
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  # Skip ETag (helps with Turbo/Devise streaming)
  config.middleware.delete Rack::ETag

  # Sessions
  config.session_store :cookie_store,
                       key: "_bonid_session",
                       expire_after: 1.week

  # Cache & Jobs
  config.cache_store = :memory_store
  # Use :async (thread-pool) instead of :inline to prevent heavy jobs
  # (e.g. WatermarkEvidenceJob) from blocking HTTP responses.
  # Production uses :solid_queue.
  config.active_job.queue_adapter = :async

  # Mailer — Letter Opener Web
  config.action_mailer.delivery_method = :letter_opener_web
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_caching = false

  # =======================================================
  # AUTO-DETECT LOCAL NETWORK IP (SAFE & ACCURATE)
  # =======================================================
  local_ip = Socket.ip_address_list
                   .select { |addr| addr.ipv4? && !addr.ipv4_loopback? && addr.ipv4_private? }
                   .map(&:ip_address)
                   .first || "localhost"

  # =======================================================
  # URL OPTIONS — NGROK WINS IF PRESENT (FIXES EMAIL LINKS)
  # =======================================================
  app_host     = ENV["APP_HOST"].presence
  app_protocol = ENV.fetch("APP_PROTOCOL", app_host.present? ? "https" : "http")
  app_port     = ENV["APP_PORT"].presence

  default_host =
    if app_host.present?
      # ✅ NGROK / Public host
      { host: app_host, protocol: app_protocol }.tap do |h|
        # only include port if explicitly set (ngrok should not have port)
        h[:port] = app_port.to_i if app_port.present?
      end
    else
      # ✅ Local fallback (use localhost for email links; local_ip still allowed via config.hosts)
      { host: "localhost", port: 3000, protocol: "http" }
    end

  # Apply to mailer + routes (Devise uses these)
  config.action_mailer.default_url_options = default_host
  Rails.application.routes.default_url_options = default_host

  # Your app-level base URL helper
  port_part = default_host[:port].present? ? ":#{default_host[:port]}" : ""
  config.bonid_base_url = "#{default_host[:protocol]}://#{default_host[:host]}#{port_part}"

  # =======================================================
  # HOST AUTHORIZATION (ALLOW LOCAL + NGROK)
  # =======================================================
  config.hosts << "localhost"
  config.hosts << local_ip
  config.hosts << /.*\.ngrok-free\.dev/
  config.hosts << ".loca.lt"

  # =======================================================
  # LOGGING & DEPRECATIONS
  # =======================================================
  config.log_level = :debug
  config.active_support.deprecation = :log
  config.active_support.disallowed_deprecation = :raise
end
