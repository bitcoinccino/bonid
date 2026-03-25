# frozen_string_literal: true

module Api
  module V1
    class VerificationsController < Api::V1::BaseController
      # If you want BaseController to enforce scopes, remove this skip.
      # For now you're skipping scope enforcement at the controller level.
      skip_before_action :enforce_scope!, raise: false

      RATE_LIMIT = 100
      WINDOW     = 15.minutes

      def verify_identity
        start_time = Time.current

        bonid = params[:bonid].to_s.strip.upcase
        return render_bad_request("Missing BonID") if bonid.blank?

        # === Rate limiting ===
        partner = Current.partner
        return render_unauthorized("Missing partner context") unless partner

        key   = "partner:#{partner.id}:api_requests"
        count = Rails.cache.read(key).to_i

        if count >= RATE_LIMIT
          set_rate_limit_headers(limit: RATE_LIMIT, remaining: 0)
          return render json: { status: "throttled", message: "Rate limit exceeded" }, status: :too_many_requests
        end

        Rails.cache.write(key, count + 1, expires_in: WINDOW)
        set_rate_limit_headers(limit: RATE_LIMIT, remaining: RATE_LIMIT - count - 1)

        # === BonID lookup ===
        user     = User.find_by(bonid: bonid)
        verified = user&.verified_identity_submission

        unless verified
          return render json: { status: "not_verified", message: "No verified BonID found" }, status: :not_found
        end

        # ✅ Choose QR source (PUBLIC first, then secure fallback)
        # - qr_png_base64: citizen/public verification QR (URL-based)
        # - secure_qr_png_base64: officer/admin secure payload QR
        qr_b64, qr_type =
          if verified.qr_png_base64.present?
            [ verified.qr_png_base64, "public" ]
          elsif verified.secure_qr_png_base64.present?
            [ verified.secure_qr_png_base64, "secure" ]
          else
            [ nil, nil ]
          end

        # Photo URL
        photo_url =
          if verified.selfie.attached?
            Rails.application.routes.url_helpers.rails_blob_url(
              verified.selfie,
              host: request.base_url
            )
          end

        payload = {
          status: "verified",
          bonid: user.bonid,
          citizen: {
            first_name:  user.first_name,
            last_name:   user.last_name,
            dob:         user.dob&.iso8601,
            sex:         user.sex,
            age:         user.age,
            address:     user.full_address,
            nationality: user.nationality
          },
          verification: {
            verified_on: verified.updated_at&.iso8601,
            verified_by: verified.reviewer&.full_name,
            qr_type:     qr_type,
            qr_url:      (qr_b64.present? ? "data:image/png;base64,#{qr_b64}" : nil),
            photo_url:   photo_url
          }
        }

        render json: payload, status: :ok

      rescue => e
        Rails.logger.error("[API verify_identity] #{e.class}: #{e.message}\n#{e.backtrace.take(8).join("\n")}")
        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      ensure
        duration_ms = ((Time.current - start_time) * 1000).round(2) rescue nil
        Rails.logger.info("[API verify_identity] duration_ms=#{duration_ms}") if duration_ms
      end

      private

      def render_bad_request(message)
        render json: { error: message }, status: :bad_request
      end

      def set_rate_limit_headers(limit:, remaining:)
        response.set_header("X-RateLimit-Limit", limit)
        response.set_header("X-RateLimit-Remaining", remaining)
      end
    end
  end
end


# # app/controllers/api/v1/verifications_controller.rb
# module Api
#   module V1
#     class VerificationsController < Api::V1::BaseController
#       before_action :authenticate_partner_and_token!

#       RATE_LIMIT = 100
#       WINDOW     = 15.minutes

#       def verify_identity
#         start_time = Time.current
#         bonid = params[:bonid].to_s.strip.upcase
#         if bonid.blank?
#           duration = (Time.current - start_time) * 1000
#           log_api_access(success: false, status: 400, message: "Missing BonID", duration: duration)
#           return render json: { error: "Missing BonID" }, status: :bad_request
#         end

#         # === Rate limiting ===
#         key = "partner:#{@current_partner.id}:api_requests"
#         count = Rails.cache.read(key).to_i
#         if count >= RATE_LIMIT
#           duration = (Time.current - start_time) * 1000
#           log_api_access(success: false, status: 429, message: "Rate limit exceeded", duration: duration)
#           set_rate_limit_headers(limit: RATE_LIMIT, remaining: 0)
#           return render json: { status: "throttled", message: "Rate limit exceeded" }, status: :too_many_requests
#         end
#         Rails.cache.write(key, count + 1, expires_in: WINDOW)
#         set_rate_limit_headers(limit: RATE_LIMIT, remaining: RATE_LIMIT - count - 1)

#         # === BonID lookup ===
#         user = User.find_by(bonid: bonid)
#         unless user&.verified_identity_submission
#           duration = (Time.current - start_time) * 1000
#           log_api_access(success: false, status: 404, message: "No verified BonID found", duration: duration)
#           return render json: { status: "not_verified", message: "No verified BonID found" }, status: :not_found
#         end

#         verified = user.verified_identity_submission
#         photo_url = verified.selfie.attached? ?
#           Rails.application.routes.url_helpers.rails_blob_url(verified.selfie, only_path: false) : nil

#         raw = {
#           status: "verified",
#           bonid: user.bonid,
#           citizen: {
#             first_name: user.first_name,
#             last_name:  user.last_name,
#             dob:        user.dob&.iso8601,
#             sex:        user.sex,
#             age:        user.age,
#             address:    user.full_address,
#             nationality: user.nationality
#           },
#           verification: {
#             verified_on: verified.updated_at&.iso8601,
#             verified_by: verified.reviewer&.full_name,
#             qr_url:      verified.qr_png_base64.present? ? "data:image/png;base64,#{verified.qr_png_base64}" : nil,
#             photo_url:   photo_url
#           }
#         }

#         duration = (Time.current - start_time) * 1000
#         log_api_access(success: true,
#                        status: 200,
#                        message: "Verified OK",
#                        duration: duration)

#         render json: raw, status: :ok

#       rescue => e
#         duration = defined?(start_time) ? (Time.current - start_time) * 1000 : 0
#         Rails.logger.error("[API::VerificationsController] #{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
#         log_api_access(success: false, status: 500, message: e.message, duration: duration)
#         render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
#       end

#       private

#       # --------------------------
#       # Authenticate API key + OAuth token
#       # --------------------------
#       def authenticate_partner_and_token!
#         header_key  = request.headers["X-Partner-Api-Key"].to_s.strip
#         auth_header = request.headers["Authorization"].to_s.strip

#         if header_key.blank?
#           return render json: { error: "Missing API key" }, status: :unauthorized
#         end

#         unless auth_header.start_with?("Bearer ")
#           return render json: { error: "Invalid Bearer token format (use 'Bearer <token>')" }, status: :unauthorized
#         end

#         bearer_token = auth_header.delete_prefix("Bearer ").strip
#         if bearer_token.blank?
#           return render json: { error: "Missing Bearer token" }, status: :unauthorized
#         end

#         # ✅ Partner lookup (uses model’s helper, no double-hash)
#         @current_partner = Partner.find_by_api_key(header_key)
#         unless @current_partner&.approved_status? && @current_partner&.verified?
#           Rails.logger.warn "[API AUTH] Invalid or inactive API key (Partner ID: #{@current_partner&.id || 'N/A'})"
#           return render json: { error: "Invalid or inactive API key" }, status: :unauthorized
#         end

#         # ✅ OAuth token lookup (safe navigation)
#         @current_token = OAuthAccessToken.active.find_by(token: bearer_token, partner_id: @current_partner.id)
#         unless @current_token&.scopes&.include?("identity:verify")
#           Rails.logger.warn "[API AUTH] Insufficient scope for partner #{@current_partner.id}"
#           return render json: { error: "Forbidden: insufficient scope" }, status: :forbidden
#         end

#         Rails.logger.info "[API AUTH] ✅ Partner #{@current_partner.name} authenticated with token (scopes: #{@current_token.scopes.join(', ')})"
#       rescue NameError => e
#         Rails.logger.error "[API AUTH] Model load error: #{e.message}"
#         render json: { error: "Authentication service unavailable" }, status: :service_unavailable
#       rescue => e
#         Rails.logger.error("[API::AuthError] #{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
#         render json: { error: "Internal authentication error" }, status: :internal_server_error
#       end


#       # --------------------------
#       # Rate limit headers
#       # --------------------------
#       def set_rate_limit_headers(limit:, remaining:)
#         response.set_header("X-RateLimit-Limit", limit)
#         response.set_header("X-RateLimit-Remaining", remaining)
#       end

#       # --------------------------
#       # Log API access
#       # --------------------------
#       def log_api_access(success: nil, status: nil, message: nil, duration: nil)
#         ApiAccessLog.create!(
#           partner_id: @current_partner&.id || 0,
#           endpoint: request.path,
#           ip_address: request.remote_ip,
#           success: success || false,
#           duration_ms: duration || 0,
#           status: status || 500,
#           response_message: message || "Unknown error",
#           metadata: {
#             controller: controller_name,
#             action: action_name,
#             params: params.permit!.to_h,
#             user_agent: request.user_agent,
#             timestamp: Time.current.iso8601
#           }
#         )
#       rescue => e
#         Rails.logger.error("[API::LogError] #{e.class}: #{e.message}")
#       end
#     end
#   end
# end
