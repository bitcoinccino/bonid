# config/environments/production.rb
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # === Core Behavior ===
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  # === Static Assets & Caching ===
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present? || ENV["RENDER"].present?
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{1.year.to_i}" }

  # === Active Storage ===
  config.active_storage.service = :tigris

  # === Security ===
  config.assume_ssl = true
  config.force_ssl  = true
  # config.ssl_options = { redirect: { exclude: ->(req) { req.path == "/up" } } }

  # === URLs & Hosts ===
  # Use environment variable so you can change the base URL later without editing code.
  default_host = ENV.fetch("BONID_BASE_URL", "https://staging.bonid.local")
  config.bonid_base_url = default_host
  Rails.application.routes.default_url_options[:host] = default_host

  # === Logging ===
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.new(Logger.new($stdout))
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = "/up"

  # === Deprecations ===
  config.active_support.report_deprecations = false

  # === Cache & Jobs ===
  config.cache_store = :solid_cache_store
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # === Mailer ===
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = {
    host: ENV.fetch("BONID_MAILER_HOST", default_host),
    protocol: "https"
  }
  config.action_mailer.default_options = { from: "noreply@verifyem.ht" }
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_ADDRESS", "smtp.yourprovider.com"),
    port: ENV.fetch("SMTP_PORT", 587),
    user_name: Rails.application.credentials.dig(:smtp, :user_name),
    password:  Rails.application.credentials.dig(:smtp, :password),
    authentication: :plain,
    enable_starttls_auto: true,
    domain: ENV.fetch("SMTP_DOMAIN", "bonid.ht")
  }

  # === I18n & DB ===
  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]
end
