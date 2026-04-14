# frozen_string_literal: true

module PartnerPortal
  class VerificationsController < PartnerPortal::BaseController
    before_action :require_verified_partner!

    def index
      @partner = @current_partner
      scope = @partner.verification_records

      # Filter by record_type if specified (e.g., ?record_type=fiscal_receipt)
      if params[:record_type].present?
        scope = scope.where(record_type: params[:record_type])
      end

      @verifications = scope.order(created_at: :desc)
                            .page(params[:page])
                            .per(20)
    end

    def show
      token = params[:verification_token].to_s.strip
      return redirect_to partner_portal_dashboard_path, alert: "Invalid verification token." if token.blank?

      submission = VisitorSubmission.find_by(verification_token: token)

      unless submission&.approved?
        # Log attempt anyway (optional)
        log_verification_attempt(submission, ok: false, reason: "not_approved_or_missing")
        return render :invalid, status: :forbidden
      end

      log_verification_attempt(submission, ok: true)

      @result = {
        ok: true,
        title: "BonTouris ID Verified",
        headline: "Valid credential",
        message: "This credential is valid and was issued by BonTouris / Verifyem.",
        bonid: submission.bonid,
        expires: submission.expires_at,
        verification_code: submission.offline_signature_code, # <- adjust to your field/presenter
        schema_version: submission.qr_schema_version # <- adjust
      }
    end

    private

    def require_verified_partner!
      unless @current_partner&.verified_at?
        redirect_to partner_portal_dashboard_path,
                    alert: "Your organization is not verified to perform scans."
      end
    end

    def log_verification_attempt(submission, ok:, reason: nil)
      return unless submission

      PartnerAccessLog.create!(
        partner_id: @current_partner&.id,
        action: "bon_touris_verify",
        target_type: "VisitorSubmission",
        target_id: submission.id,
        ok: ok,
        reason: reason,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    rescue => e
      Rails.logger.warn("Partner verify log failed: #{e.class}: #{e.message}")
    end
  end
end
