require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Bonid
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    config.assets.paths << Rails.root.join("app/assets/builds")

    # Add lib subdirectories to autoload, excluding non-Ruby files
    config.autoload_lib(ignore: %w[assets tasks])
    config.autoload_paths << Rails.root.join('app/pdfs')

    # ✅ Set Haiti time zone (UTC-4 with DST)
    config.time_zone = "America/Port-au-Prince"
    config.active_record.default_timezone = :local
     
    # Additional config...
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
