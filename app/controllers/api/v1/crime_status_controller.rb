# frozen_string_literal: true

# app/controllers/api/v1/crime_status_controller.rb
#
# Crime Status API for verified partners (embassies, consulates, etc.)
# Provides crime involvement status checks for BonID/BonTouris holders.
#
# Security:
# - Requires dual authentication (API key + OAuth token)
# - Scope-based access control (crime:status)
# - Rate limited to prevent abuse
# - All access logged for audit trail
# - Response signing for integrity verification
#
# Endpoints:
#   GET /api/v1/crime_status/:bonid - Check crime involvement status
#
module Api
  module V1
    class CrimeStatusController < Api::V1::BaseController
      include ResponseSigner

      # Skip default auth, use dual auth for this sensitive endpoint
      skip_before_action :authenticate_partner_or_token!, raise: false
      skip_before_action :enforce_scope!, raise: false
      before_action :authenticate_partner_and_token!
      before_action :validate_bonid_format

      # Rate limiting configuration
      RATE_LIMIT = 50              # Requests per window
      RATE_WINDOW = 15.minutes     # Rate limit window
      REQUIRED_SCOPE = "crime:status"

      # GET /api/v1/crime_status/:bonid
      #
      # Returns crime involvement status for a BonID or BonTouris holder.
      #
      # Response tiers based on partner access level:
      # - Tier 1 (Basic): has_record (yes/no), severity_level (if yes)
      # - Tier 2 (Summary): + involvement count, roles, latest incident date
      # - Tier 3 (Full): + incident details (requires citizen consent)
      #
      # @param bonid [String] The BonID or BonTouris number to check
      # @return [JSON] Crime status response
      #
      def show
        start_time = Time.current

        # Rate limiting check
        return if rate_limit_exceeded?

        # Lookup person by BonID or BonTouris
        result = CrimeStatusService.new(
          bonid: @bonid,
          partner: @current_partner,
          access_tier: determine_access_tier
        ).call

        if result[:success]
          payload = build_success_response(result[:data])
          log_api_access(success: true, status: 200, message: "Crime status retrieved", duration: duration_ms(start_time))
          sign_response(payload)
          render json: payload, status: :ok
        else
          payload = build_error_response(result[:error], result[:code])
          log_api_access(success: false, status: result[:code], message: result[:error], duration: duration_ms(start_time))
          sign_response(payload)
          render json: payload, status: result[:status]
        end
      rescue StandardError => e
        Rails.logger.error("[API::CrimeStatusController] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        log_api_access(success: false, status: 500, message: e.message, duration: duration_ms(start_time))

        payload = build_error_response("Internal server error", 500)
        sign_response(payload)
        render json: payload, status: :internal_server_error
      end

      private

      # Validate BonID format before processing
      def validate_bonid_format
        @bonid = params[:bonid].to_s.strip.upcase

        if @bonid.blank?
          payload = build_error_response("Missing BonID parameter", 400)
          sign_response(payload)
          render json: payload, status: :bad_request
          return
        end

        # Validate format: BonID (DV-1989-M-SE-P8697XDS) or BonTouris (T-XX-YYYY-S-CC-P-XXXXXX)
        bonid_pattern = /^[A-Z]{2,3}-\d{4}-[MFX]-[A-Z]+-[A-Z]\d{4}[A-Z0-9]{3}$/i
        bontouris_pattern = /^T-[A-Z]{2}-\d{4}-[MFX]-[A-Z]{2,3}-P-\d{6}$/
        suffix_pattern = /^\d{6}$/ # 6-digit lookup

        unless @bonid.match?(bonid_pattern) || @bonid.match?(bontouris_pattern) || @bonid.match?(suffix_pattern)
          payload = build_error_response("Invalid BonID format. Expected format: DV-1989-M-SE-P8697XDS or T-JS-1990-M-US-P-988455", 400)
          sign_response(payload)
          render json: payload, status: :bad_request
        end
      end

      # Dual authentication: API key + OAuth token required
      def authenticate_partner_and_token!
        header_key = request.headers["X-Partner-Api-Key"].to_s.strip
        auth_header = request.headers["Authorization"].to_s.strip

        # Check API key
        if header_key.blank?
          return render_auth_error("Missing API key header (X-Partner-Api-Key)")
        end

        # Check Bearer token format
        unless auth_header.start_with?("Bearer ")
          return render_auth_error("Invalid Authorization header format. Use 'Bearer <token>'")
        end

        bearer_token = auth_header.gsub(/^Bearer\s+/i, "").strip
        if bearer_token.blank?
          return render_auth_error("Missing Bearer token")
        end

        # Partner lookup via API key (SHA256 with bcrypt fallback)
        @current_partner = find_partner_by_api_key(header_key)

        unless @current_partner&.verified_at.present? && @current_partner.active?
          Rails.logger.warn("[API AUTH] Invalid or inactive partner: #{header_key[0..12]}...")
          return render_auth_error("Invalid or inactive API key")
        end

        # OAuth token validation
        @current_token = ::OauthAccessToken.active.find_by(
          token: bearer_token,
          partner_id: @current_partner.id
        )

        unless @current_token
          Rails.logger.warn("[API AUTH] Token not found or expired: #{bearer_token[0..12]}...")
          return render_auth_error("Invalid or expired OAuth token")
        end

        # Scope verification
        token_scopes = Array(@current_token.scopes).map(&:to_s)
        unless token_scopes.include?(REQUIRED_SCOPE)
          Rails.logger.warn("[API AUTH] Token missing scope '#{REQUIRED_SCOPE}' (has: #{token_scopes.join(', ')})")
          payload = {
            status: "forbidden",
            error: "Insufficient scope. Required: #{REQUIRED_SCOPE}",
            code: 403,
            timestamp: Time.current.iso8601
          }
          sign_response(payload)
          render json: payload, status: :forbidden
        end
      end

      # Find partner by API key using SHA256 digest (with bcrypt fallback)
      def find_partner_by_api_key(key)
        digest = Digest::SHA256.hexdigest(key)
        partner = ::Partner.find_by(api_key_digest: digest)

        return partner if partner

        # Bcrypt fallback for legacy keys
        ::Partner.where.not(api_key_digest: nil).detect do |p|
          next false unless p.api_key_digest.to_s.start_with?("$2")
          begin
            BCrypt::Password.new(p.api_key_digest).is_password?(key)
          rescue BCrypt::Errors::InvalidHash
            false
          end
        end
      end

      # Determine access tier based on partner sector and permissions
      def determine_access_tier
        return :tier_1 unless @current_partner

        # Embassy/consulate/government partners get higher access
        # Using 'sector' field which stores partner type
        sector = @current_partner.sector.to_s.downcase

        if sector.in?(%w[law_enforcement pnh])
          # Haitian law enforcement owns the data — full access
          :tier_3
        elsif sector.in?(%w[government ministry municipality oni cep dgi onaca])
          # Haitian government agencies — summary access
          :tier_2
        else
          # Everyone else (embassies, banks, fintech) — basic yes/no only
          :tier_1
        end
      end

      # Rate limiting check
      def rate_limit_exceeded?
        cache_key = "partner:#{@current_partner.id}:crime_status_requests"
        count = Rails.cache.read(cache_key).to_i

        if count >= RATE_LIMIT
          set_rate_limit_headers(limit: RATE_LIMIT, remaining: 0)
          payload = {
            status: "rate_limited",
            error: "Rate limit exceeded. Try again in #{RATE_WINDOW.to_i / 60} minutes.",
            code: 429,
            retry_after: RATE_WINDOW.to_i,
            timestamp: Time.current.iso8601
          }
          sign_response(payload)
          log_api_access(success: false, status: 429, message: "Rate limit exceeded", duration: 0)
          render json: payload, status: :too_many_requests
          return true
        end

        Rails.cache.write(cache_key, count + 1, expires_in: RATE_WINDOW)
        set_rate_limit_headers(limit: RATE_LIMIT, remaining: RATE_LIMIT - count - 1)
        false
      end

      # Build success response payload
      def build_success_response(data)
        {
          status: "success",
          bonid: @bonid,
          crime_status: data,
          partner: @current_partner.name,
          access_tier: determine_access_tier,
          timestamp: Time.current.iso8601,
          api_version: "1.0.0"
        }
      end

      # Build error response payload
      def build_error_response(message, code)
        {
          status: "error",
          error: message,
          code: code,
          bonid: @bonid,
          endpoint: request.path,
          timestamp: Time.current.iso8601
        }
      end

      # Render authentication error
      def render_auth_error(message)
        payload = {
          status: "unauthorized",
          error: message,
          code: 401,
          timestamp: Time.current.iso8601
        }
        sign_response(payload)
        render json: payload, status: :unauthorized
      end

      # Set rate limit headers
      def set_rate_limit_headers(limit:, remaining:)
        response.set_header("X-RateLimit-Limit", limit)
        response.set_header("X-RateLimit-Remaining", remaining)
        response.set_header("X-RateLimit-Reset", (Time.current + RATE_WINDOW).utc.iso8601)
      end

      # Log API access for audit trail
      def log_api_access(success:, status:, message:, duration:)
        ApiAccessLog.create!(
          partner_id: @current_partner&.id,
          endpoint: request.path,
          ip_address: request.remote_ip,
          success: success,
          status: status,
          response_message: message,
          duration_ms: duration,
          metadata: {
            controller: controller_name,
            action: action_name,
            bonid: @bonid,
            access_tier: determine_access_tier,
            user_agent: request.user_agent,
            timestamp: Time.current.iso8601
          }
        )
      rescue StandardError => e
        Rails.logger.error("[API LOG ERROR] Failed to log access: #{e.message}")
      end

      # Calculate duration in milliseconds
      def duration_ms(start_time)
        ((Time.current - start_time) * 1000).round(2)
      end
    end
  end
end
