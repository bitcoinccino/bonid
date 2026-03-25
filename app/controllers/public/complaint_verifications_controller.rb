# frozen_string_literal: true

# Public::ComplaintVerificationsController
#
# No authentication required — designed to be hit by anyone scanning the QR code
# printed on an IGPNH complaint certificate (police officers, OPC staff, judges).
#
# Returns a tamper-evidence check:
#   ✅ VALID   — the certificate data matches the stored HMAC signature
#   ❌ INVALID — data has been altered; signature mismatch
#   ❌ NOT FOUND — tracking number doesn't exist

module Public
  class ComplaintVerificationsController < ApplicationController
    layout "public"

    skip_before_action :authenticate_user!,      raise: false
    skip_before_action :enforce_namespace_access, raise: false

    def show
      tracking = params[:tracking_number].to_s.strip.upcase

      @complaint = OfficerComplaint.find_by(tracking_number: tracking)

      unless @complaint
        @error = :not_found
        render status: :not_found and return
      end

      @valid          = @complaint.certificate_valid?
      @signed_at      = @complaint.certificate_signed_at
      @checksum       = @complaint.certificate_checksum

      # Safe public fields — no PII beyond what's on the printed certificate
      @reference      = @complaint.certificate_reference
      @status_label   = @complaint.status_label
      @status_color   = @complaint.status_color
      @filed_at       = @complaint.submitted_at
      @allegation     = @complaint.allegation_category
      @department     = @complaint.department&.name
      @directorate    = @complaint.routing_directorate_name

      # Scan log — helps detect if someone is trying lots of numbers
      Rails.logger.info(
        "[ComplaintVerify] Scanned #{@reference} — valid=#{@valid} " \
        "ip=#{request.remote_ip}"
      )
    end
  end
end
