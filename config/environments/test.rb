# config/environments/test.rb
require "active_support/core_ext/integer/time"

Rails.application.configure do
  # === Core Behavior ===
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = true

  # === Static Files & Caching ===
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=3600" }
  config.cache_store = :null_store

  # === Error Handling ===
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false

  # === Active Storage ===
  config.active_storage.service = :test

  # === Mailer ===
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: "http://example.com" }

  # === Deprecations ===
  config.active_support.deprecation = :stderr

  # === Callbacks & View Annotations ===
  config.action_controller.raise_on_missing_callback_actions = true
  # config.action_view.annotate_rendered_view_with_filenames = true

  # === URL Helpers for Blob URLs ===
  Rails.application.routes.default_url_options[:host] = "http://example.com"

  # === Debug Logging (for API key tests) ===
  config.log_level = :debug
  config.logger = Logger.new($stdout)
end
