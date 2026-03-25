# frozen_string_literal: true

module PartnerPortal
  class QrScansController < PartnerPortal::BaseController
    before_action :require_verified_partner!

    # POST /qr/resolve
    # params: { payload: "..." } or { verification_token: "..." }
    def resolve
      token =
        params[:verification_token].presence ||
        extract_token_from_payload(params[:payload].to_s)

      return render json: { ok: false, error: "invalid_qr" }, status: :unprocessable_entity if token.blank?

      submission = VisitorSubmission.find_by(verification_token: token)

      unless submission&.approved?
        log_scan(submission, ok: false, reason: "not_approved_or_missing")
        return render json: { ok: false, error: "not_valid" }, status: :forbidden
      end

      log_scan(submission, ok: true)

      render json: {
        ok: true,
        bonid: submission.bonid,
        status: "valid",
        expires: submission.expires_at,
        schema_version: submission.qr_schema_version
      }
    end

    private

    def require_verified_partner!
      unless @current_partner&.verified?
        render json: { ok: false, error: "partner_not_verified" }, status: :unauthorized
        return
      end
    end

    def extract_token_from_payload(payload)
      return "" if payload.blank?

      begin
        uri = URI.parse(payload)
        parts = uri.path.to_s.split("/")
        parts.last.to_s
      rescue
        payload.strip
      end
    end

    def log_scan(submission, ok:, reason: nil)
      return unless submission

      QrScanLog.create!(
        partner: @current_partner,
        visitor_submission_id: submission.id,
        ok: ok,
        reason: reason,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    rescue => e
      Rails.logger.warn("QR scan log failed: #{e.class}: #{e.message}")
    end
  end
end
