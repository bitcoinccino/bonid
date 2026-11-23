# frozen_string_literal: true

module Api
  module V1
    class BonidStatusController < Api::V1::BaseController
      include ResponseSigner

      # BaseController handles ALL authentication
      # before_action :authenticate_partner_or_token!

      def show
        start_time = Time.current
        bonid = params[:bonid].to_s.strip.upcase

        if bonid.blank?
          return render_json_error("Missing BonID parameter", :bad_request, 400)
        end

        user = User.find_by(bonid: bonid)
        unless user&.verified_identity_submission
          ApiAccessLog.log(
            partner: @current_partner,
            endpoint: request.path,
            ip: request.remote_ip,
            success: false,
            status: 404,
            message: "BonID not found or not verified",
            metadata: { bonid: bonid, reason: "not_found_or_unverified", user_agent: request.user_agent }
          )
          return render_json_error("BonID not found or not verified", :not_found, 404)
        end

        submission = user.verified_identity_submission

        # Verification status only — no name, DOB, address, photo or QR.
        # Personal data needs the citizen's consent (GET /api/v1/identity/:bonid
        # with a consent_token), the same rule as the identity endpoint.
        payload = {
          status: "verified",
          bonid: user.bonid,
          verification: {
            verified_on: safe_time(submission.updated_at),
            expires_at:  safe_time(submission.expires_at),
            reference:   submission.uuid # dispute reference; never the reviewer
          },
          access_level: "verification_only",
          hint:      "Identity details require citizen consent: use GET /api/v1/identity/:bonid?consent_token=...",
          partner:   @current_partner.name,
          timestamp: safe_time(Time.current)
        }

        payload = stringify_dates(payload)
        sign_response(payload)

        ApiAccessLog.log(
          partner: @current_partner,
          user: user,
          endpoint: request.path,
          ip: request.remote_ip,
          success: true,
          status: 200,
          message: "Verified successfully",
          duration_ms: ((Time.current - start_time) * 1000).round(2),
          metadata: {
            bonid: bonid,
            controller: self.class.name,
            user_agent: request.user_agent
          }
        )

        render json: payload, status: :ok
      rescue => e
        Rails.logger.error("[BonID API ERROR] #{e.class}: #{e.message}")

        ApiAccessLog.log(
          partner: @current_partner,
          endpoint: request.path,
          ip: request.remote_ip,
          success: false,
          status: 500,
          message: "Internal Error: #{e.message}",
          metadata: { controller: self.class.name, exception: e.class.name, message: e.message }
        )

        render json: { error: "Internal error: #{e.message}" }, status: :internal_server_error
      end

      private

      def render_json_error(message, status_sym, code)
        payload = {
          status: Rack::Utils::SYMBOL_TO_STATUS_CODE[status_sym] < 500 ? "error" : "internal_error",
          message: message,
          code: code,
          endpoint: request.path,
          timestamp: safe_time(Time.current)
        }
        payload = stringify_dates(payload)
        sign_response(payload)
        render json: payload, status: status_sym
      end

      def safe_time(value)
        return nil if value.nil?
        value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
      end

      def stringify_dates(obj)
        case obj
        when Hash
          obj.transform_values { |v| stringify_dates(v) }
        when Array
          obj.map { |v| stringify_dates(v) }
        when Time, DateTime, Date, ActiveSupport::TimeWithZone
          obj.iso8601 rescue obj.to_s
        else
          obj
        end
      end
    end
  end
end
