source "https://rubygems.org"

# Core framework
gem "rails", "~> 8.0.2"

# Database
gem "pg", "~> 1.1"

# Web server
gem "puma", ">= 5.0"

# Asset pipeline & frontend
gem "propshaft"
gem "cssbundling-rails", "~> 1.4"
gem "jsbundling-rails", "~> 1.3"
gem "bootstrap", "~> 5.3.3"
# gem "importmap-rails" # Optional: only if still needed for some static JS
gem "turbo-rails"
gem "stimulus-rails"

# Utilities
gem "geocoder"
gem "prawn"
gem "rqrcode"
gem 'rqrcode_png'
gem "country_select"
gem "jbuilder"
gem "image_processing", "~> 1.2"
gem 'kaminari'
gem 'kaminari-bootstrap'
gem 'chunky_png'
gem 'wicked_pdf'
gem 'wkhtmltopdf-binary'


# Background jobs & caching
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "bootsnap", require: false

# Security
gem "rack-attack"

# Admin, Auth, and Policies
gem "activeadmin"
gem "devise"
gem "pundit"

# Forms
gem "simple_form"

# Deployment
gem "kamal", require: false
gem "thruster", require: false

# Environment variables
gem "dotenv-rails", groups: [:development, :test]

# Development & Testing
group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "letter_opener"
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

# Windows compatibility
gem "tzinfo-data", platforms: %i[windows jruby]

gem "dockerfile-rails", ">= 1.7", :group => :development

gem "aws-sdk-s3", "~> 1.186", :require => false
