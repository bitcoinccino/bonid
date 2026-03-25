# frozen_string_literal: true

# Rails 8 injects rate limiting into ALL controllers via:
#   ActionController::RateLimiting
#
# The callback signature rate_limit!(request, response)
# breaks HTML controllers because Rails sometimes calls it with 0 args.
#
# We disable Rails rate limiting for all non-API controllers.
# API controllers keep rate limiting fully intact.

Rails.application.config.to_prepare do
  ActiveSupport.on_load(:action_controller) do
    next unless defined?(ActionController::RateLimiting)

    # Only keep rate limiting for controllers under Api::V1
    unless self.name.start_with?("Api::V1")
      skip_before_action :rate_limit!, raise: false rescue nil
    end
  end
end
