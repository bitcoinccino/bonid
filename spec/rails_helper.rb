# frozen_string_literal: true

require 'spec_helper'
require 'faker'
require 'factory_bot_rails'
require 'bcrypt'

ENV['RAILS_ENV'] ||= 'test'
abort("The Rails environment is running in production mode!") if Rails.env.production?

require File.expand_path('../config/environment', __dir__)
require 'rspec/rails'

# Rails 8 CSRF fix
unless ActionController::Base.method_defined?(:verify_authenticity_token)
  ActionController::Base.define_method(:verify_authenticity_token) { }
end

# Load support files
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Ensure exceptions render JSON instead of crashing
Rails.application.env_config["action_dispatch.show_exceptions"] = true
Rails.application.env_config["action_dispatch.show_detailed_exceptions"] = false

# Apply pending migrations
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# shoulda-matchers
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join('spec/fixtures') ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
end
