# frozen_string_literal: true

require "rack/request"
require "json"
require "digest"

module Middleware
  class ConditionalApiKeyAuth
    SAFE_SEGMENTS = %w[
      approve_consent
      citizen/approve_consent
      healthcheck
      public
      status
    ].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      req = Rack::Request.new(env)

      return @app.call(env) unless api_request?(req)
      return @app.call(env) if safe_path?(req.path)

      key = extract_api_key(req).to_s.strip
      return unauthorized("Missing API key") if key.empty?
      return unauthorized("Malformed API key") unless key.start_with?("bonid_")

      partner = authenticate_partner(key)
      return unauthorized("Invalid or inactive API key") unless partner

      # ✅ Make partner available to controllers
      env["current_partner"] = partner

      # ✅ Prefer Current over Thread.current (but keep both if legacy code reads Thread.current)
      Current.partner = partner if defined?(Current)
      Thread.current[:current_partner] = partner

      @app.call(env)
    rescue => e
      internal_error(e)
    ensure
      # ✅ prevent leakage between requests
      Thread.current[:current_partner] = nil
      Current.partner = nil if defined?(Current)
    end

    private

    def api_request?(req)
      req.path.start_with?("/api/v1") &&
        req.get_header("HTTP_ACCEPT")&.include?("application/json")
    end

    def safe_path?(path)
      SAFE_SEGMENTS.any? { |seg| path.include?(seg) }
    end

    def extract_api_key(req)
      req.get_header("HTTP_X_PARTNER_API_KEY") ||
        req.get_header("HTTP_X_API_KEY")
    end

    def authenticate_partner(key)
      digest = Digest::SHA256.hexdigest(key)
      p = Partner.find_by(api_key_digest: digest)

      return nil unless p
      return nil unless p.respond_to?(:active?) ? p.active? : true
      return nil unless p.verified_at.present? || p.try(:status) == "active"

      p
    end

    def unauthorized(msg)
      [ 401, json_header, [ { error: msg }.to_json ] ]
    end

    def internal_error(e)
      Rails.logger.error "[ConditionalApiKeyAuth] #{e.class} - #{e.message}"
      [ 500, json_header, [ { error: "Internal error: #{e.class} - #{e.message}" }.to_json ] ]
    end

    def json_header
      { "Content-Type" => "application/json" }
    end
  end
end


# # # frozen_string_literal: true

# # module Middleware
# #   class ConditionalApiKeyAuth
# #     def initialize(app)
# #       @app = app
# #     end

# #     def call(env)
# #       req = Rack::Request.new(env)
# #       path = req.path
# #       partner = nil

# #       return @app.call(env) unless path.start_with?("/api/v1")

# #       if path.match?(%r{/(citizen/approve_consent|approve_consent|public|healthcheck|status)})
# #         Rails.logger.info "[Middleware::ConditionalApiKeyAuth] ⏭️ Skipping API key check for #{path}"
# #         return @app.call(env)
# #       end

# #       key = req.get_header("HTTP_X_PARTNER_API_KEY") || req.get_header("HTTP_X_API_KEY")
# #       return unauthorized("Missing API key") unless key.present?
# #       return unauthorized("Malformed API key. Must start with 'bonid_'") unless key.start_with?("bonid_")

# #       hashed_key = Digest::SHA256.hexdigest(key)
# #       partner = Partner.find_by(api_key_digest: hashed_key)

# #       unless partner&.active? && (partner.verified_at.present? || partner.try(:status) == "active")
# #         Rails.logger.warn "[API AUTH] ❌ Invalid or inactive API key: #{key}"
# #         return unauthorized("Invalid or inactive API key")
# #       end

# #       env["current_partner"] = partner
# #       Thread.current[:current_partner] = partner
# #       Rails.logger.info "[API AUTH] ✅ Partner #{partner.slug} authenticated successfully."

# #       @app.call(env)
# #     rescue => e
# #       handle_error(e, req, partner)
# #     end

# #     private

# #     def unauthorized(message)
# #       [
# #         401,
# #         { "Content-Type" => "application/json" },
# #         [ { error: message }.to_json ]
# #       ]
# #     end

# #     def handle_error(e, req, partner)
# #       Rails.logger.error "[API AUTH] Middleware Error: #{e.class} — #{e.message}"

# #       if defined?(ApiAccessLog)
# #         ApiAccessLog.create!(
# #           partner: partner,
# #           endpoint: req&.path,
# #           ip_address: req&.ip,
# #           success: false,
# #           response_message: "Middleware Error: #{e.message}",
# #           metadata: {
# #             controller: "Middleware::ConditionalApiKeyAuth",
# #             exception: e.class.name,
# #             message: e.message,
# #             backtrace: Array(e.backtrace).first(3),
# #             timestamp: Time.current.iso8601
# #           }
# #         ) rescue nil
# #       end

# #       [
# #         500,
# #         { "Content-Type" => "application/json" },
# #         [ { error: "Internal error: #{e.class} - #{e.message}" }.to_json ]
# #       ]
# #     end
# #   end
# # end
