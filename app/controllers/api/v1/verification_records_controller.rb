# frozen_string_literal: true

# app/controllers/api/v1/verifications_controller.rb
module Api
  module V1
    class VerificationsController < Api::V1::BaseController
      # This endpoint requires BOTH api_key + bearer token, so we override base auth.
      skip_before_action :authenticate_partner_or_token!, raise: false
      skip_before_action :enforce_scope!, raise: false

      before_action :authenticate_partner_and_token!

      RATE_LIMIT = 100
      WINDOW     = 15.minutes
      REQUIRED_SCOPE = "verifications:verify_identity"

      def verify_identity
        start_time = Time.current

        bonid =
          params[:bonid].presence ||
          params.dig(:verification, :bonid).presence

        bonid = bonid.to_s.strip.upcase

        if bonid.blank?
          duration = (Time.current - start_time) * 1000
          log_api_access(success: false, status: 400, message: "Missing BonID", duration: duration)
          return render json: { error: "Missing BonID" }, status: :bad_request
        end

        # === Rate limiting ===
        key   = "partner:#{@current_partner.id}:api_requests"
        count = Rails.cache.read(key).to_i

        if count >= RATE_LIMIT
          duration = (Time.current - start_time) * 1000
          log_api_access(success: false, status: 429, message: "Rate limit exceeded", duration: duration)
          set_rate_limit_headers(limit: RATE_LIMIT, remaining: 0)
          return render json: { status: "throttled", message: "Rate limit exceeded" }, status: :too_many_requests
        end

        Rails.cache.write(key, count + 1, expires_in: WINDOW)
        set_rate_limit_headers(limit: RATE_LIMIT, remaining: RATE_LIMIT - count - 1)

        # === BonID lookup ===
        user = User.find_by(bonid: bonid)

        unless user&.verified_identity_submission
          duration = (Time.current - start_time) * 1000
          log_api_access(success: false, status: 404, message: "No verified BonID found", duration: duration)
          return render json: { status: "not_verified", message: "No verified BonID found" }, status: :not_found
        end

        verified = user.verified_identity_submission

        photo_url =
          if verified.selfie.attached?
            Rails.application.routes.url_helpers.rails_blob_url(verified.selfie, only_path: false)
          end

        # ✅ Your system is writing secure_qr_png_base64 — return it (fallback to legacy)
        qr_b64 = verified.secure_qr_png_base64.presence || verified.qr_png_base64.presence

        raw = {
          status: "verified",
          bonid: user.bonid,
          citizen: {
            first_name: user.first_name,
            last_name:  user.last_name,
            dob:        user.dob&.iso8601,
            sex:        user.sex,
            age:        user.age,
            address:    user.full_address,
            nationality: user.nationality
          },
          verification: {
            verified_on: verified.updated_at&.iso8601,
            verified_by: verified.reviewer&.full_name,
            qr_url:      qr_b64 ? "data:image/png;base64,#{qr_b64}" : nil,
            qr_type:     verified.secure_qr_png_base64.present? ? "secure" : (verified.qr_png_base64.present? ? "public" : nil),
            photo_url:   photo_url
          }
        }

        duration = (Time.current - start_time) * 1000
        log_api_access(success: true, status: 200, message: "Verified OK", duration: duration)

        render json: raw, status: :ok
      rescue => e
        duration = defined?(start_time) ? (Time.current - start_time) * 1000 : 0
        Rails.logger.error("[API::VerificationsController] #{e.class}: #{e.message}\n#{e.backtrace.take(8).join("\n")}")
        log_api_access(success: false, status: 500, message: e.message, duration: duration)
        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      end

      private

      # --------------------------
      # Require BOTH: API key + Bearer token + scope
      # --------------------------
      def authenticate_partner_and_token!
        header_key   = request.headers["X-Partner-Api-Key"].to_s.strip
        auth_header  = request.headers["Authorization"].to_s.strip

        return render json: { error: "Missing API key" }, status: :unauthorized if header_key.blank?

        unless auth_header.start_with?("Bearer ")
          return render json: { error: "Invalid Bearer token format (use 'Bearer <token>')" }, status: :unauthorized
        end

        bearer_token = auth_header.gsub(/^Bearer\s+/i, "").strip
        return render json: { error: "Missing Bearer token" }, status: :unauthorized if bearer_token.blank?

        # Partner lookup (SHA256 digest)
        partner_digest = Digest::SHA256.hexdigest(header_key)
        @current_partner = ::Partner.find_by(api_key_digest: partner_digest)

        # Optional fallback for bcrypt digests
        if @current_partner.nil?
          @current_partner = ::Partner.where.not(api_key_digest: nil).detect do |partner|
            digest = partner.api_key_digest.to_s
            next false unless digest.start_with?("$2")
            begin
              BCrypt::Password.new(digest).is_password?(header_key)
            rescue BCrypt::Errors::InvalidHash
              false
            end
          end
        end

        unless @current_partner&.verified_at.present? && @current_partner.active?
          Rails.logger.warn "[API AUTH] Invalid or inactive API key: #{header_key[0..12]}..."
          return render json: { error: "Invalid or inactive API key" }, status: :unauthorized
        end

        # OAuth token lookup (MUST match partner)
        @current_token = ::OauthAccessToken.active.find_by(token: bearer_token, partner_id: @current_partner.id)

        unless @current_token
          Rails.logger.warn "[API AUTH] Token not found or expired: #{bearer_token[0..12]}..."
          return render json: { error: "Invalid or expired token" }, status: :unauthorized
        end

        # Scope check
        unless Array(@current_token.scopes).map(&:to_s).include?(REQUIRED_SCOPE)
          Rails.logger.warn "[API AUTH] Token missing required scope '#{REQUIRED_SCOPE}' (has: #{Array(@current_token.scopes).join(', ')})"
          return render json: { error: "Forbidden: insufficient scope" }, status: :forbidden
        end

        Rails.logger.info "[API AUTH] ✅ Partner #{@current_partner.name} (ID: #{@current_partner.id}) + token OK (scopes: #{Array(@current_token.scopes).join(', ')})"
      rescue => e
        Rails.logger.error "[API AUTH] Unexpected error: #{e.class} - #{e.message}\n#{e.backtrace.take(8).join("\n")}"
        render json: { error: "Internal authentication error" }, status: :internal_server_error
      end

      # --------------------------
      # Rate limit headers
      # --------------------------
      def set_rate_limit_headers(limit:, remaining:)
        response.set_header("X-RateLimit-Limit", limit)
        response.set_header("X-RateLimit-Remaining", remaining)
      end

      # --------------------------
      # Log API access
      # --------------------------
      def log_api_access(success: nil, status: nil, message: nil, duration: nil)
        ApiAccessLog.create!(
          partner_id: @current_partner&.id || 0,
          endpoint: request.path,
          ip_address: request.remote_ip,
          success: success || false,
          duration_ms: duration || 0,
          status: status || 500,
          response_message: message || "Unknown error",
          metadata: {
            controller: controller_name,
            action: action_name,
            params: params.permit!.to_h,
            user_agent: request.user_agent,
            timestamp: Time.current.iso8601
          }
        )
      rescue => e
        Rails.logger.error("[API::LogError] #{e.class}: #{e.message}")
      end
    end
  end
end
