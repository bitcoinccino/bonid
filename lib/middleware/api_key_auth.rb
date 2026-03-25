# frozen_string_literal: true

module Middleware
  class ApiKeyAuth
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

      key = extract_api_key(req)
      return unauthorized("Missing API key") if key.blank?

      partner = authenticate_partner(key)
      return unauthorized("Invalid or inactive API key") unless partner

      env["current_partner"] = partner
      Thread.current[:current_partner] = partner

      @app.call(env)

    rescue => e
      internal_error(e)
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
      req.get_header("HTTP_X_API_KEY") ||
        req.get_header("HTTP_X_PARTNER_API_KEY")
    end

    def authenticate_partner(key)
      hashed = Digest::SHA256.hexdigest(key)
      Partner.find_by(api_key_digest: hashed).tap do |p|
        return false unless p&.active?
        return false unless p.verified_at.present? || p.status == "active"
      end
    end

    def unauthorized(msg)
      [ 401, json_header, [ { error: msg }.to_json ] ]
    end

    def internal_error(e)
      Rails.logger.error "[ApiKeyAuth] #{e.class} - #{e.message}"
      [ 500, json_header, [ { error: "Internal error: #{e.class} - #{e.message}" }.to_json ] ]
    end

    def json_header
      { "Content-Type" => "application/json" }
    end
  end
end


# # frozen_string_literal: true

# module Middleware
#   class ApiKeyAuth
#     def initialize(app)
#       @app = app
#     end

#     def call(env)
#       req = Rack::Request.new(env)
#       path = req.path
#       partner = nil

#       return @app.call(env) unless path.start_with?("/api/v1")

#       if path.match?(%r{/(approve_consent|citizen/approve_consent|public|healthcheck|status)})
#         Rails.logger.info "[Middleware::ApiKeyAuth] ⏭️ Skipping API key auth for #{path}"
#         return @app.call(env)
#       end

#       key = req.get_header("HTTP_X_API_KEY") || req.get_header("HTTP_X_PARTNER_API_KEY")
#       return unauthorized("Missing API key") unless key.present?

#       partner = authenticate_partner(key)
#       unless partner&.active? && (partner.verified_at.present? || partner.try(:status) == "active")
#         return unauthorized("Invalid or inactive API key")
#       end

#       env["current_partner"] = partner
#       Thread.current[:current_partner] = partner

#       start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
#       status, headers, response = @app.call(env)
#       duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
#       log_access(req, partner, path, status, duration_ms)

#       [ status, headers, response ]
#     rescue => e
#       handle_middleware_error(e, req, partner)
#     end

#     private

#     def authenticate_partner(key)
#       Partner.where.not(api_key_digest: nil).find do |p|
#         digest = p.api_key_digest.to_s
#         next false if digest.blank?

#         if digest.start_with?("$2")
#           BCrypt::Password.new(digest).is_password?(key)
#         else
#           Digest::SHA256.hexdigest(key) == digest
#         end
#       rescue BCrypt::Errors::InvalidHash
#         false
#       end
#     end

#     def log_access(req, partner, path, status, duration_ms)
#       ApiAccessLog.create!(
#         partner: partner,
#         endpoint: path,
#         ip_address: req.ip,
#         success: (200..299).include?(status),
#         metadata: {
#           controller: "Middleware::ApiKeyAuth",
#           status: status,
#           duration_ms: duration_ms,
#           ip: req.ip,
#           timestamp: Time.current.iso8601
#         }
#       )
#     rescue => e
#       Rails.logger.error "[APIKeyAuth] Log Error (non-fatal): #{e.class} — #{e.message}"
#     end

#     def handle_middleware_error(e, req, partner)
#       Rails.logger.error "[APIKeyAuth] Middleware Error: #{e.class} — #{e.message}"

#       ApiAccessLog.create!(
#         partner: partner,
#         endpoint: req&.path,
#         ip_address: req&.ip,
#         success: false,
#         response_message: "Middleware Error: #{e.message}",
#         metadata: {
#           controller: "Middleware::ApiKeyAuth",
#           exception: e.class.name,
#           message: e.message,
#           backtrace: Array(e.backtrace).first(3),
#           timestamp: Time.current.iso8601
#         }
#       ) rescue nil

#       [
#         500,
#         { "Content-Type" => "application/json" },
#         [ { error: "Internal error: #{e.class} - #{e.message}" }.to_json ]
#       ]
#     end

#     def unauthorized(message)
#       [
#         401,
#         { "Content-Type" => "application/json" },
#         [ { error: message }.to_json ]
#       ]
#     end
#   end
# end
