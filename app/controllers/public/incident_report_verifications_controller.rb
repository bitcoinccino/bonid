# frozen_string_literal: true

# Public::IncidentReportVerificationsController
#
# No authentication required — designed to be hit by anyone scanning the QR code
# printed on a PNH officer incident report (judges, prosecutors, defense lawyers,
# international observers, OPC investigators).
#
# Returns a tamper-evidence check:
#   ✅ VALID   — the report data matches the stored HMAC signature
#   ❌ TAMPERED — data has been altered; signature mismatch
#   ❌ NOT FOUND — report_id doesn't exist in the PNH database
#
# Privacy: exposes only crime_type, occurred_at, location and status.
# Names, BonIDs, and descriptions of persons involved are NEVER exposed.

module Public
  class IncidentReportVerificationsController < ApplicationController
    layout "public"

    skip_before_action :authenticate_user!,      raise: false
    skip_before_action :enforce_namespace_access, raise: false

    def show
      report_id = params[:report_id].to_s.strip.upcase

      @report = IncidentReport.find_by(report_id: report_id)

      unless @report
        @error = :not_found
        render status: :not_found and return
      end

      @valid       = @report.report_valid?
      @signed_at   = @report.report_signed_at
      @checksum    = @report.report_checksum
      @report_id   = @report.report_id
      @crime_type  = @report.crime_type
      @occurred_at = @report.occurred_at
      @location    = @report.full_location
      @status      = @report.status

      # Audit log — helps detect enumeration attempts
      Rails.logger.info(
        "[IncidentReportVerify] Scanned #{@report_id} — valid=#{@valid} ip=#{request.remote_ip}"
      )
    end
  end
end
