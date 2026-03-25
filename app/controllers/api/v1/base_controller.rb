# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      include RateLimitable
      include PlanEnforceable
      include ResponseSigner

      protect_from_forgery with: :null_session

      before_action :ensure_api_request!
      before_action :authenticate_partner_or_token!
      before_action :set_current_context
      before_action :enforce_scope!, if: -> { @oauth_token.present? }

      around_action :log_partner_api_access
      after_action  :set_bonid_api_headers

      private

      # ============================================================
      # 🛑 Prevent HTML controllers from running API auth
      # ============================================================
      def ensure_api_request!
        return if request.path.start_with?("/api/") || request.format.json?

        self.class.skip_before_action :authenticate_partner_or_token!, raise: false
        self.class.skip_before_action :enforce_scope!, raise: false
        self.class.skip_around_action :log_partner_api_access, raise: false

        throw :abort
      end

      # ============================================================
      # 🔑 Dual Auth — Bearer token OR X-Partner-Api-Key
      # ============================================================
      def authenticate_partner_or_token!
        auth_header = request.headers["Authorization"].to_s.strip
        api_key     = request.headers["X-Partner-Api-Key"].to_s.strip

        if auth_header.start_with?("Bearer ")
          token_value = auth_header.split.last.to_s.strip
          return render_unauthorized("Missing Bearer token") if token_value.blank?

          # IMPORTANT: Your model is OauthAccessToken (not OAuthAccessToken)
          @oauth_token = ::OauthAccessToken.active.find_by(token: token_value)
          return render_unauthorized("Invalid or expired access token") unless @oauth_token

          @partner = @oauth_token.partner
          request.headers["X-BonID-Scopes"] = Array(@oauth_token.scopes).join(",")

          render_unauthorized("Inactive partner") unless @partner&.active? && @partner.verified_at.present?
        elsif api_key.present?
          authenticate_partner!
        else
          render_unauthorized("Missing credentials")
        end
      rescue => e
        Rails.logger.error("[API AUTH] #{e.class}: #{e.message}")
        render json: { status: "unauthorized", error: "Internal authentication error", timestamp: Time.current.iso8601 },
               status: :unauthorized
      end

      # ============================================================
      # 🔒 Partner API-key auth (SHA256 digest, bcrypt supported)
      # ============================================================
      def authenticate_partner!
        return true if Rails.env.test?

        header_key = request.headers["X-Partner-Api-Key"].to_s.strip
        return render_unauthorized("Missing API key") if header_key.blank?

        # Fast path: SHA256 digest lookup (your current dev setup)
        sha_digest = Digest::SHA256.hexdigest(header_key)
        @partner = ::Partner.find_by(api_key_digest: sha_digest)

        # Debug: log digest comparison
        if @partner.nil?
          Rails.logger.warn("[API AUTH DEBUG] SHA256 of received key: #{sha_digest}")
          all_digests = ::Partner.where.not(api_key_digest: nil).pluck(:id, :name, :api_key_digest)
          all_digests.each do |id, name, stored|
            Rails.logger.warn("[API AUTH DEBUG] Partner ##{id} (#{name}) stored digest: #{stored[0..15]}... (len=#{stored.length})")
          end
        end

        # Slow fallback: bcrypt digests (only if you have any)
        if @partner.nil?
          @partner = ::Partner.where.not(api_key_digest: nil).detect do |partner|
            digest = partner.api_key_digest.to_s
            next false if digest.blank?
            next false unless digest.start_with?("$2")

            begin
              BCrypt::Password.new(digest).is_password?(header_key)
            rescue BCrypt::Errors::InvalidHash
              false
            end
          end
        end

        return render_unauthorized("Invalid API key") unless @partner
        render_unauthorized("Inactive partner") unless @partner.active? && @partner.verified_at.present?
      end

      # ============================================================
      # ✅ Scopes
      # ============================================================
      def enforce_scope!
        token_scopes = Array(@oauth_token&.scopes).map(&:to_s)

        if token_scopes.blank?
          token_scopes = request.headers["X-BonID-Scopes"].to_s.split(",").map(&:strip).reject(&:blank?)
        end

        required = required_scope_for_request
        return if required.blank?

        unless token_scopes.include?(required)
          payload = {
            status: "forbidden",
            error: "Forbidden: insufficient scope",
            required_scope: required,
            scopes: token_scopes,
            timestamp: Time.current.iso8601
          }
          sign_response(payload)
          render json: payload, status: :forbidden
        end
      end

      def required_scope_for_request
        key = "#{self.class.name}##{action_name}"

        {
          # Identity verification endpoints (legacy)
          "Api::V1::VerificationsController#verify_identity" => "verifications:verify_identity",

          # Identity API endpoints (new unified)
          "Api::V1::IdentityController#show" => "identity:verify",
          "Api::V1::IdentityController#status" => "identity:verify",

          # Crime Status API endpoints
          "Api::V1::CrimeStatusController#show" => "crime:status",
          "Api::V1::IncidentReportsController#index" => "crime:reports",
          "Api::V1::IncidentReportsController#certificate" => "crime:certificate",

          # Officer misconduct summary API — verified partners only
          "Api::V1::OfficerComplaintsController#summary" => "officer:complaints",

          # Fiscal receipt API — DGI / Immigration
          "Api::V1::FiscalReceiptsController#lookup"  => "fiscal_receipts:read",
          "Api::V1::FiscalReceiptsController#consume" => "fiscal_receipts:consume"
        }[key]
      end

      # ============================================================
      # 🚨 Unified Unauthorized
      # ============================================================
      def render_unauthorized(message)
        payload = {
          status: "unauthorized",
          error: message,
          timestamp: Time.current.iso8601
        }
        sign_response(payload)
        render json: payload, status: :unauthorized
      end

      # ============================================================
      # 🧠 Context
      # ============================================================
      def set_current_context
        Current.user = nil
        %i[current_user current_citizen current_officer current_admin_user].each do |scope|
          next unless respond_to?(scope, true)
          u = public_send(scope)
          if u.present?
            Current.user = u
            break
          end
        end

        Current.partner = @partner
        Current.request = request
      rescue => e
        Rails.logger.error("[CurrentContext] #{e.class}: #{e.message}")
      end

      # ============================================================
      # 🪵 Partner API logging (safe)
      # ============================================================
      def log_partner_api_access
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        request_start = Time.current

        begin
          yield
        rescue => e
          Rails.logger.error("[PartnerApiLog] #{e.class}: #{e.message}")
          raise
        ensure
          # ✅ FIX: return (NOT next) — next is only valid in loops
          return unless @partner

          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration_ms = ((end_time - start_time) * 1000).round(2)

          # Async: offload API logging to background job (saves ~15-25ms in production)
          begin
            LogPartnerApiAccessJob.perform_later(
              partner_id: @partner.id,
              endpoint: request.path,
              request_method: request.method,
              status_code: response.status,
              response_time_ms: duration_ms,
              ip_address: request.remote_ip,
              user_agent: request.user_agent,
              requested_at: request_start.iso8601
            )
          rescue => e
            Rails.logger.error("[PartnerApiLog] enqueue failed: #{e.class}: #{e.message}")
          end

          # Stamp consent grant last activity (non-blocking, best-effort)
          stamp_consent_grant_access! if response.status.to_i < 300
        end
      end

      def status_category(code)
        case code.to_i
        when 200..299 then :success
        when 400..499 then :client_error
        else :server_error
        end
      end

      def safe_response_body
        b = response.body.to_s
        b.length > 500 ? b.truncate(500) : b
      rescue
        ""
      end

      # ============================================================
      # 📊 Stamp ConsentGrant last activity after successful API call
      # ============================================================
      def stamp_consent_grant_access!
        return unless @partner

        # Resolve citizen: prefer OAuth token, fall back to bonid param
        citizen = @oauth_token&.citizen
        if citizen.nil? && params[:bonid].present?
          citizen = User.find_by(bonid: params[:bonid].to_s.strip.upcase)
        end

        return unless citizen

        # Async: offload consent grant stamping to background job (saves ~5-10ms)
        RecordConsentAccessJob.perform_later(citizen_id: citizen.id, partner_id: @partner.id)
      rescue => e
        Rails.logger.warn("[BaseController#stamp_consent_grant_access!] #{e.class}: #{e.message}")
      end

      # ============================================================
      # Headers
      # ============================================================
      def set_bonid_api_headers
        response.set_header("X-BonID-API-Version", "1.3.0")
        response.set_header("X-BonID-Environment", Rails.env)
        if @oauth_token.present?
          response.set_header("X-BonID-Granted-Scopes", Array(@oauth_token.scopes).join(","))
        end
      end
    end
  end
end

# # frozen_string_literal: true

# module Api
#   module V1
#     class BaseController < ApplicationController
#       include PartnerAuthenticatable
#       include RateLimitable
#       include ResponseSigner

#       protect_from_forgery with: :null_session

#       # ============================================================
#       # 🔒 Auth + Context Hooks
#       # ============================================================
#       before_action :authenticate_partner_or_token!
#       before_action :set_current_context
#       before_action :enforce_scope!, if: -> { defined?(Current.partner) && Current.partner.present? }

#       # ============================================================
#       # 📊 Logging + Response Meta
#       # ============================================================
#       around_action :log_api_access
#       after_action  :set_bonid_api_headers

#       private

#       # ============================================================
#       # 🔑 Dual Authenticator — API Key or OAuth Token
#       # ============================================================
#       def authenticate_partner_or_token!
#         auth_header = request.headers["Authorization"].to_s
#         api_key     = request.headers["X-Partner-Api-Key"].to_s.strip

#         if auth_header.start_with?("Bearer ")
#           token_value = auth_header.split.last
#           token = OAuthAccessToken.active.find_by(token: token_value)
#           return render_unauthorized("Invalid or expired access token") unless token

#           @partner = token.partner
#           request.headers["X-BonID-Scopes"] = token.scopes.join(",")
#           Rails.logger.info("[AUTH] ✅ OAuth token verified for #{@partner.slug}")
#         elsif api_key.present?
#           authenticate_partner! # fallback to API-key auth
#         else
#           render_unauthorized("Missing credentials")
#         end
#       end

#       # ============================================================
#       # ✅ Partner Authentication (SHA256 + BCrypt)
#       # ============================================================
#       def authenticate_partner!
#         return true if Rails.env.test? || defined?(RSpec)

#         if request.path.match?(/citizen\/approve_consent/) || params[:grant_token].present?
#           Rails.logger.info("[API AUTH] ⏭️ Skipping partner auth for citizen consent flow.")
#           return true
#         end

#         header_key = request.headers["X-Partner-Api-Key"].to_s.strip
#         return render_unauthorized("Missing API key") if header_key.blank?

#         @partner = ::Partner.where.not(api_key_digest: nil).find do |partner|
#           digest = partner.api_key_digest.to_s
#           next false if digest.blank?

#           begin
#             digest.start_with?("$2") ? BCrypt::Password.new(digest).is_password?(header_key) :
#                                        Digest::SHA256.hexdigest(header_key) == digest
#           rescue BCrypt::Errors::InvalidHash
#             false
#           end
#         end

#         return render_unauthorized("Invalid API key") if @partner.nil?
#         return render_unauthorized("Inactive or unverified partner") unless @partner.active? && @partner.verified_at.present?

#         Rails.logger.info("[API AUTH] ✅ Partner authenticated: #{@partner.name} (#{@partner.slug})")
#         true
#       end

#       # ============================================================
#       # 🚨 Unified Unauthorized Renderer
#       # ============================================================
#       def render_unauthorized(message)
#         payload = {
#           status: "unauthorized",
#           error: message,
#           code: 401,
#           timestamp: Time.current.iso8601
#         }
#         sign_response(payload) if respond_to?(:sign_response)
#         render json: payload, status: :unauthorized
#       end

#       # ============================================================
#       # 🌍 Global BonID API Response Headers
#       # ============================================================
#       def set_bonid_api_headers
#         response.set_header("X-BonID-API-Version", "1.3.0")
#         response.set_header("X-BonID-Environment", Rails.env)
#         response.set_header("X-BonID-Spec-Path", "/api/swagger")
#         response.set_header("X-BonID-Scopes", request.headers["X-BonID-Scopes"]) if request.headers["X-BonID-Scopes"].present?
#       end

#       # ============================================================
#       # 🧠 Current Context
#       # ============================================================
#       def set_current_context
#         Current.user = nil

#         %i[current_user current_citizen current_officer current_admin_user].each do |scope|
#           next unless respond_to?(scope, true)
#           candidate = public_send(scope)
#           if candidate.present?
#             Current.user = candidate
#             break
#           end
#         end

#         Current.partner = defined?(@partner) ? @partner : nil
#         Current.request = request
#       rescue => e
#         Rails.logger.error("[CurrentContext] #{e.class}: #{e.message}")
#       end

#       # ============================================================
#       # ⚙️ Scope Enforcement (for OAuth)
#       # ============================================================
#       def enforce_scope!
#         return unless request.headers["Authorization"].present?
#         token_scopes = request.headers["X-BonID-Scopes"].to_s.split(",")
#         required_scope = "#{controller_name}:#{action_name}"

#         unless token_scopes.include?(required_scope)
#           Rails.logger.warn("[SCOPE] ⛔️ Missing scope #{required_scope} for partner #{Current.partner&.slug}")
#           render json: { error: "Forbidden: insufficient scope" }, status: :forbidden
#         end
#       rescue => e
#         Rails.logger.error("[Scope Enforcement Error] #{e.message}")
#       end

#       # ============================================================
#       # 🪵 Access Logging (duration, success, metadata)
#       # ============================================================
#       def log_api_access
#         start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
#         yield
#       rescue => e
#         ApiAccessLog.log(
#           partner: @partner,
#           user: Current.user,
#           endpoint: "#{controller_path}##{action_name}",
#           ip: request.remote_ip,
#           success: false,
#           status: 500,
#           message: e.message,
#           metadata: { params: request.filtered_parameters.except(:controller, :action), backtrace: e.backtrace.first(5) }
#         )
#         raise e
#       ensure
#         end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
#         duration = ((end_time - start_time) * 1000).round(2)

#         ApiAccessLog.log(
#           partner: @partner,
#           user: Current.user,
#           endpoint: "#{controller_path}##{action_name}",
#           ip: request.remote_ip,
#           success: response.successful?,
#           status: response.status,
#           message: response.message || response.body&.truncate(200),
#           duration_ms: duration,
#           metadata: {
#             method: request.method,
#             path: request.path,
#             params: request.filtered_parameters.except(:controller, :action),
#             env: Rails.env,
#             request_id: request.uuid
#           }
#         )
#       end
#     end
#   end
# end
