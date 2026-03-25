# frozen_string_literal: true

require_relative "boot"
require "rails/all"

# 🚑 Rails 8 temporary fix – define verify_authenticity_token early
begin
  require "action_controller/base"
  unless ActionController::Base.method_defined?(:verify_authenticity_token)
    ActionController::Base.define_method(:verify_authenticity_token) { }
  end
rescue NameError, LoadError
  # Ignore
end

Bundler.require(*Rails.groups)

module Bonid
  class Application < Rails::Application
    # === Rails Defaults ===
    config.load_defaults 8.0

    # === Time Zone ===
    config.time_zone = "America/Port-au-Prince"
    config.active_record.default_timezone = :utc

    # === Autoload & Eager Load Paths ===
    config.autoload_paths += %W[
      #{Rails.root}/lib
      #{Rails.root}/app/pdfs
    ]

    config.eager_load_paths += %W[
      #{Rails.root}/lib
      #{Rails.root}/app/pdfs
    ]

    # === Public Base URL ===
    config.bonid_base_url = ENV.fetch("BONID_BASE_URL", "https://bonid.ht")

    # === Frontend Build Folder ===
    config.paths.add "app/assets/builds", with: [ "app/assets/builds" ]

    # === Security Middleware Stack ===
    config.middleware.use Rack::Attack

    # KEEP ApiKeyAuth
    if defined?(Middleware::ApiKeyAuth)
      config.middleware.insert_after Rack::Attack, Middleware::ApiKeyAuth
    end

    # ❌ REMOVE ConditionalApiKeyAuth COMPLETELY
    # Do not require it
    # Do not insert it
    # Do not load it

    # === Chartkick + Groupdate ===
    if defined?(Groupdate)
      Groupdate.time_zone = "America/Port-au-Prince"
      Groupdate.week_start = :monday
    end

    # === Internationalization ===
    config.i18n.available_locales = %i[en fr ht]
    config.i18n.default_locale = :en

# === Propshaft Asset Paths (REQUIRED) ===
config.assets.paths << Rails.root.join("app/assets/builds")
config.assets.paths << Rails.root.join("app/assets/images")
config.assets.paths << Rails.root.join("app/assets/fonts")
config.assets.paths << Rails.root.join("app/assets/sounds")

    # === App Version Loader ===
    config.after_initialize do
      require Rails.root.join("config/version.rb")
    end

    # === Generators ===
    config.generators do |g|
      g.assets false
      g.helper false
      g.test_framework :rspec, fixture: false
    end
  end
end
