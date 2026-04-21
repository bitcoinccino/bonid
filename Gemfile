source "https://rubygems.org"

# === Core Framework ===
gem "rails", "~> 8.0.2"
gem "puma", ">= 5.0"
gem "pg", "~> 1.1"
gem "redis"

# === Asset Pipeline & Frontend ===
gem "propshaft"
gem "cssbundling-rails", "~> 1.4"
gem "jsbundling-rails", "~> 1.3"
gem "bootstrap", "~> 5.3.3"
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails"

# === Visualization & Analytics ===
gem "chartkick"              # Chart visualization
gem "groupdate"              # Time-based ActiveRecord grouping
gem "geocoder"               # Geolocation for addresses
gem "open_location_code"     # Plus Codes / Map encoding
gem "rolify"

# === File Handling & Documents ===
gem "prawn"                  # PDF generation
gem "wicked_pdf"             # HTML to PDF rendering
gem "wkhtmltopdf-binary"     # wkhtmltopdf binary
gem "rqrcode"
gem "rqrcode_png"
gem "chunky_png"
gem "image_processing", "~> 1.2"
gem "activestorage-validator"
gem "openssl"
gem "ed25519", "~> 1.4"      # Ed25519 signatures for BonID QR offline verification
gem "secret_sharing", "~> 0.0" # Shamir 5-of-9 split for the CEP tally-decryption ceremony

# === JSON Schema & Data Validation ===
gem "json_schemer"           # Partner schema validation
gem "rails-i18n"
# === Forms & Pagination ===
gem "simple_form"
gem "country_select"
gem "kaminari"
gem "kaminari-bootstrap"
gem "pagy", "~> 9.4"

# === Background Jobs / Realtime / Cache ===
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "bootsnap", require: false

# === Security ===
gem "rack-attack"

# === Authentication / Authorization ===
gem "devise", "~> 4.9"
gem "devise_invitable", github: "scambra/devise_invitable"
gem "devise-two-factor"
gem "pundit"
gem "activeadmin"

# === Deployment & Ops ===
gem "kamal", require: false
gem "thruster", require: false

# === Utilities ===
gem "foreman"                # Procfile dev server
gem "jbuilder"               # JSON views (for API)
gem "dotenv-rails", groups: %i[development test]
gem "aws-sdk-s3", "~> 1.186", require: false
gem "aws-sdk-rekognition", "~> 1.0", require: false  # Face matching for identity verification
gem "aws-sdk-textract", "~> 1.0", require: false      # Passport OCR for BonTouris
gem "rack-cors", require: "rack/cors"

# === API Documentation ===
gem "rswag-api"
gem "rswag-ui"
gem "blueprinter"
gem "rswag-specs"
gem "active_model_serializers", "~> 0.10.15"

# === Payment Processing ===
gem "stripe", "~> 17.0"
gem "stripe-rails"  # Rails wrapper for Stripe models/callbacks

# === Development & Testing ===
group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "faker", "~> 3.3"
  gem "shoulda-matchers", "~> 5.0"
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.5"
end

group :development do
  gem "web-console"
  gem "letter_opener"
  gem "letter_opener_web"
  gem "dockerfile-rails", ">= 1.7"
  gem "traceroute"           # Find unused routes
  gem "debride"              # Find unused methods
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

# === Windows Compatibility ===
gem "tzinfo-data", platforms: %i[windows jruby]
