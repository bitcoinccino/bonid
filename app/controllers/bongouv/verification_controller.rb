# frozen_string_literal: true

# ==========================================================================
# Bongouv::VerificationController — Public receipt verification endpoint.
#
# When someone scans the receipt QR code, they hit:
#   GET /v/:token
#
# No authentication required — this is a public verification page.
# Shows a clean, high-trust page confirming (or denying) the receipt.
#
# Audit: Every scan is logged anonymously to detect reuse/fraud.
# ==========================================================================
module Bongouv
  class VerificationController < ActionController::Base
    layout false
    helper BongouvHelper
    helper ApplicationHelper

    # GET /v/:token
    def show
      @token = params[:token]
      result = Bongouv::ReceiptSigner.verify_by_token(@token)

      @status  = result[:status]
      @payment = result[:payment]
      @payload = result[:payload]

      # Log the scan anonymously for audit trail
      log_scan(@token, @status) if @payment.present?

      render :show
    end

    private

    def log_scan(token, status)
      Rails.logger.info(
        "[Bongouv::Verify] token=#{token} status=#{status} " \
        "ip=#{request.remote_ip} ua=#{request.user_agent&.truncate(80)}"
      )

      # Increment scan count in provider_response for fraud detection
      if @payment&.provider_response&.dig("bongouv_seal").present?
        seal = @payment.provider_response["bongouv_seal"]
        seal["scan_count"] = (seal["scan_count"] || 0) + 1
        seal["last_scanned_at"] = Time.current.iso8601
        @payment.update_column(:provider_response, @payment.provider_response)
      end
    rescue => e
      Rails.logger.error "[Bongouv::Verify] scan log failed: #{e.message}"
    end
  end
end
