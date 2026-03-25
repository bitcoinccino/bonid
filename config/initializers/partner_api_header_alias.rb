# frozen_string_literal: true

class PartnerApiHeaderAlias
  def initialize(app)
    @app = app
  end

  def call(env)
    api = env["HTTP_X_API_KEY"]
    partner = env["HTTP_X_PARTNER_API_KEY"]

    # Normalize + duplicate both ways
    if partner.present?
      env["HTTP_X_API_KEY"] ||= partner
    elsif api.present?
      env["HTTP_X_PARTNER_API_KEY"] ||= api
    end

    @app.call(env)
  end
end

# # frozen_string_literal: true

# # Duplicates X-Partner-Api-Key and X-Api-Key headers so Rack::Attack and APIKeyAuth
# # can both see them.

# class PartnerApiHeaderAlias
#   def initialize(app)
#     @app = app
#   end

#   def call(env)
#     if env["HTTP_X_PARTNER_API_KEY"].present?
#       env["HTTP_X_API_KEY"] ||= env["HTTP_X_PARTNER_API_KEY"]
#     elsif env["HTTP_X_API_KEY"].present?
#       env["HTTP_X_PARTNER_API_KEY"] ||= env["HTTP_X_API_KEY"]
#     end
#     @app.call(env)
#   end
# end

# # Insert before Rack::Attack so the header aliasing happens early
# Rails.application.config.middleware.insert_before Rack::Attack, PartnerApiHeaderAlias
