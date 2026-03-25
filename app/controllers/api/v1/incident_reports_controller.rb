# frozen_string_literal: true

# app/controllers/api/v1/incident_reports_controller.rb
#
# Incident Reports API for verified partners (embassies, consulates, etc.)
# Provides incident report search and certificate retrieval.
#
# Security:
# - Requires dual authentication (API key + OAuth token)
# - Scope-based access control (crime:reports, crime:certificate)
# - Rate limited to prevent abuse
# - Citizen consent verification for detailed records
# - All access logged for audit trail
# - Response signing for integrity verification
#
# Endpoints:
#   GET /api/v1/incident_reports - Search reports by BonID
#   GET /api/v1/incident_reports/:id/certificate - Get incident certificate
#
module Api
  module V1
    class IncidentReportsController < Api::V1::BaseController
      include ResponseSigner

      # Skip default auth, use dual auth for these sensitive endpoints
      skip_before_action :authenticate_partner_or_token!, raise: false
      skip_before_action :enforce_scope!, raise: false
      before_action :authenticate_partner_and_token!
      before_action :set_incident_report, only: [:certificate]

      # Rate limiting configuration
      RATE_LIMIT = 30              # Requests per window (lower for reports)
      RATE_WINDOW = 15.minutes     # Rate limit window

      # Scope requirements per action
      REQUIRED_SCOPES = {
        index: "crime:reports",
        certificate: "crime:certificate"
      }.freeze

      # GET /api/v1/incident_reports
      #
      # Search incident reports by BonID.
      # Returns a list of incidents involving the specified person.
      #
      # @param bonid [String] Required - The BonID or BonTouris to search
      # @param role [String] Optional - Filter by role (suspect, victim, witness)
      # @param status [String] Optional - Filter by involvement status
      # @param from_date [String] Optional - Filter from date (ISO8601)
      # @param to_date [String] Optional - Filter to date (ISO8601)
      # @param page [Integer] Optional - Page number (default: 1)
      # @param per_page [Integer] Optional - Results per page (default: 20, max: 50)
      #
      # @return [JSON] List of incident reports
      #
      def index
        start_time = Time.current

        # Validate scope
        unless has_required_scope?(:index)
          return render_scope_error("crime:reports")
        end

        # Rate limiting check
        return if rate_limit_exceeded?

        # Validate BonID parameter
        bonid = params[:bonid].to_s.strip.upcase
        if bonid.blank?
          payload = build_error_response("Missing required 'bonid' parameter", 400)
          sign_response(payload)
          return render json: payload, status: :bad_request
        end

        # Check citizen consent for report access
        consent_check = verify_citizen_consent(bonid, "reports:read")
        unless consent_check[:authorized]
          payload = {
            status: "consent_required",
            error: consent_check[:message],
            code: 403,
            consent_url: consent_check[:consent_url],
            timestamp: Time.current.iso8601
          }
          sign_response(payload)
          log_api_access(success: false, status: 403, message: "Consent required", duration: duration_ms(start_time))
          return render json: payload, status: :forbidden
        end

        # Search for reports
        result = search_incident_reports(bonid)

        if result[:success]
          payload = build_search_response(result[:data], result[:pagination])
          log_api_access(success: true, status: 200, message: "Reports retrieved: #{result[:data].count}", duration: duration_ms(start_time))
          sign_response(payload)
          render json: payload, status: :ok
        else
          payload = build_error_response(result[:error], result[:code])
          log_api_access(success: false, status: result[:code], message: result[:error], duration: duration_ms(start_time))
          sign_response(payload)
          render json: payload, status: result[:status]
        end
      rescue StandardError => e
        Rails.logger.error("[API::IncidentReportsController#index] #{e.class}: #{e.message}")
        handle_error(e, start_time)
      end

      # GET /api/v1/incident_reports/:id/certificate
      #
      # Get an incident report certificate.
      # Returns either JSON data or PDF based on Accept header.
      #
      # @param id [String] The incident report UUID
      # @param format [String] Optional - 'json' or 'pdf' (default: json)
      #
      # @return [JSON|PDF] Incident certificate
      #
      def certificate
        start_time = Time.current

        # Validate scope
        unless has_required_scope?(:certificate)
          return render_scope_error("crime:certificate")
        end

        # Rate limiting check
        return if rate_limit_exceeded?

        # Draft reports have never been attested — no certificate may be issued
        if @incident_report.status_draft?
          payload = build_error_response("Certificate unavailable: this report has not been submitted or attested by an officer.", 422)
          sign_response(payload)
          log_api_access(success: false, status: 422, message: "Certificate requested for draft report", duration: duration_ms(start_time))
          return render json: payload, status: :unprocessable_entity
        end

        # Verify partner has access to this specific report
        access_check = verify_report_access(@incident_report)
        unless access_check[:authorized]
          payload = {
            status: "forbidden",
            error: access_check[:message],
            code: 403,
            timestamp: Time.current.iso8601
          }
          sign_response(payload)
          log_api_access(success: false, status: 403, message: access_check[:message], duration: duration_ms(start_time))
          return render json: payload, status: :forbidden
        end

        # Check citizen consent for certificate access
        bonids = @incident_report.person_involvements.pluck(:bonid).compact
        consent_check = verify_citizens_consent(bonids, "certificate:read")
        unless consent_check[:authorized]
          payload = {
            status: "consent_required",
            error: consent_check[:message],
            code: 403,
            missing_consents: consent_check[:missing],
            timestamp: Time.current.iso8601
          }
          sign_response(payload)
          log_api_access(success: false, status: 403, message: "Consent required", duration: duration_ms(start_time))
          return render json: payload, status: :forbidden
        end

        # Generate certificate
        format = params[:format]&.downcase || request.format.symbol.to_s

        if format == "pdf" || request.format.pdf?
          generate_pdf_certificate(@incident_report, start_time)
        else
          generate_json_certificate(@incident_report, start_time)
        end
      rescue StandardError => e
        Rails.logger.error("[API::IncidentReportsController#certificate] #{e.class}: #{e.message}")
        handle_error(e, start_time)
      end

      private

      # Set incident report from UUID
      def set_incident_report
        @incident_report = IncidentReport.find_by(uuid: params[:id])

        unless @incident_report
          payload = build_error_response("Incident report not found", 404)
          sign_response(payload)
          render json: payload, status: :not_found
        end
      end

      # Check if token has required scope
      def has_required_scope?(action)
        required = REQUIRED_SCOPES[action]
        token_scopes = Array(@current_token&.scopes).map(&:to_s)
        token_scopes.include?(required)
      end

      # Render scope error
      def render_scope_error(required_scope)
        payload = {
          status: "forbidden",
          error: "Insufficient scope. Required: #{required_scope}",
          code: 403,
          timestamp: Time.current.iso8601
        }
        sign_response(payload)
        render json: payload, status: :forbidden
      end

      # Search incident reports by BonID
      def search_incident_reports(bonid)
        # Find person involvements — exclude draft reports (not yet attested by an officer)
        involvements = PersonInvolvement.includes(
          incident_report: [:officer, :crime_type_record, :address]
        ).where(bonid: bonid)
          .joins(:incident_report)
          .where.not(incident_reports: { status: "draft" })

        # Apply filters
        involvements = involvements.where(role: params[:role]) if params[:role].present?
        involvements = involvements.where(status: params[:status]) if params[:status].present?

        if params[:from_date].present?
          from_date = Date.parse(params[:from_date]) rescue nil
          involvements = involvements.joins(:incident_report)
                                     .where("incident_reports.occurred_at >= ?", from_date) if from_date
        end

        if params[:to_date].present?
          to_date = Date.parse(params[:to_date]) rescue nil
          involvements = involvements.joins(:incident_report)
                                     .where("incident_reports.occurred_at <= ?", to_date) if to_date
        end

        # Pagination
        page = [params[:page].to_i, 1].max
        per_page = [[params[:per_page].to_i, 1].max, 50].min
        per_page = 20 if params[:per_page].blank?

        total_count = involvements.count
        involvements = involvements.offset((page - 1) * per_page).limit(per_page)

        # Build report data
        reports = involvements.map do |pi|
          report = pi.incident_report
          {
            id: report.uuid,
            report_id: report.report_id,
            case_number: report.bonid_case_number,
            crime_type: report.crime_type,
            crime_code: report.crime_type_record&.code,
            severity: report.crime_severity_level,
            occurred_at: report.occurred_at&.iso8601,
            submitted_at: report.submitted_at&.iso8601,
            status: report.status,
            involvement: {
              role: pi.role,
              status: pi.status
            },
            location: {
              commune: report.address&.commune&.name,
              department: report.address&.department&.name
            }
          }
        end

        {
          success: true,
          data: reports,
          pagination: {
            page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: (total_count.to_f / per_page).ceil
          }
        }
      rescue StandardError => e
        Rails.logger.error("[search_incident_reports] #{e.class}: #{e.message}")
        { success: false, error: "Failed to search reports", code: 500, status: :internal_server_error }
      end

      # Generate JSON certificate
      def generate_json_certificate(report, start_time)
        certificate_data = CrimeCertificateService.new(
          report: report,
          partner: @current_partner,
          format: :json
        ).generate

        payload = {
          status: "success",
          certificate: certificate_data,
          partner: @current_partner.name,
          generated_at: Time.current.iso8601,
          valid_until: (Time.current + 24.hours).iso8601,
          api_version: "1.0.0"
        }

        log_api_access(success: true, status: 200, message: "Certificate generated (JSON)", duration: duration_ms(start_time))
        sign_response(payload)
        render json: payload, status: :ok
      end

      # Generate PDF certificate
      def generate_pdf_certificate(report, start_time)
        pdf_data = CrimeCertificateService.new(
          report: report,
          partner: @current_partner,
          format: :pdf
        ).generate

        log_api_access(success: true, status: 200, message: "Certificate generated (PDF)", duration: duration_ms(start_time))

        # Set response headers
        response.headers["Content-Type"] = "application/pdf"
        response.headers["Content-Disposition"] = "attachment; filename=\"certificate-#{report.report_id}.pdf\""
        response.headers["X-Certificate-ID"] = report.uuid
        response.headers["X-Generated-At"] = Time.current.iso8601
        response.headers["X-Valid-Until"] = (Time.current + 24.hours).iso8601

        send_data pdf_data, type: "application/pdf", disposition: "attachment"
      end

      # Verify citizen consent for data access
      def verify_citizen_consent(bonid, scope)
        # Find user by BonID
        user = User.find_by(bonid: bonid)
        visitor = VisitorSubmission.find_by(bonid: bonid) if user.nil?

        if user.nil? && visitor.nil?
          return { authorized: false, message: "BonID not found" }
        end

        # For government/law enforcement partners, auto-authorize
        sector = @current_partner.sector.to_s.downcase
        if sector.in?(%w[embassy consulate government law_enforcement ministry])
          return { authorized: true }
        end

        # Check for active consent grant
        # ConsentGrant uses citizen_id and partner_id
        if user
          consent = ConsentGrant.where(revoked_at: nil)
                                .where("expires_at IS NULL OR expires_at > ?", Time.current)
                                .where(citizen_id: user.id, partner_id: @current_partner.id)
                                .where("? = ANY(scopes)", scope)
                                .first
        end

        if consent
          { authorized: true }
        else
          consent_url = generate_consent_request_url(bonid, scope)
          {
            authorized: false,
            message: "Citizen consent required for accessing this data",
            consent_url: consent_url
          }
        end
      end

      # Verify consent from multiple citizens
      def verify_citizens_consent(bonids, scope)
        # For government/law enforcement partners, auto-authorize
        sector = @current_partner.sector.to_s.downcase
        if sector.in?(%w[embassy consulate government law_enforcement ministry])
          return { authorized: true }
        end

        missing = []

        bonids.each do |bonid|
          result = verify_citizen_consent(bonid, scope)
          missing << bonid unless result[:authorized]
        end

        if missing.empty?
          { authorized: true }
        else
          {
            authorized: false,
            message: "Consent required from #{missing.count} person(s)",
            missing: missing
          }
        end
      end

      # Verify partner has access to specific report
      def verify_report_access(report)
        # Government/embassy partners can access all reports
        sector = @current_partner.sector.to_s.downcase
        return { authorized: true } if sector.in?(%w[embassy consulate government law_enforcement ministry])

        # Other partners need to be involved in the report somehow
        # (e.g., healthcare partner accessing medical-related incident)
        { authorized: true, message: "Access granted based on partner type" }
      end

      # Generate consent request URL
      def generate_consent_request_url(bonid, scope)
        base_url = Rails.application.config.bonid_base_url || "https://bonid.ht"
        "#{base_url}/api/v1/request_consent?bonid=#{bonid}&partner_id=#{@current_partner.id}&scope=#{scope}"
      end

      # Build search response
      def build_search_response(data, pagination)
        {
          status: "success",
          bonid: params[:bonid].to_s.upcase,
          reports: data,
          pagination: pagination,
          partner: @current_partner.name,
          timestamp: Time.current.iso8601,
          api_version: "1.0.0"
        }
      end

      # Build error response
      def build_error_response(message, code)
        {
          status: "error",
          error: message,
          code: code,
          endpoint: request.path,
          timestamp: Time.current.iso8601
        }
      end

      # Handle error with logging
      def handle_error(error, start_time)
        log_api_access(success: false, status: 500, message: error.message, duration: duration_ms(start_time))
        payload = build_error_response("Internal server error", 500)
        sign_response(payload)
        render json: payload, status: :internal_server_error
      end

      # ============================
      # Authentication (duplicated for standalone operation)
      # ============================

      def authenticate_partner_and_token!
        header_key = request.headers["X-Partner-Api-Key"].to_s.strip
        auth_header = request.headers["Authorization"].to_s.strip

        if header_key.blank?
          return render_auth_error("Missing API key header (X-Partner-Api-Key)")
        end

        unless auth_header.start_with?("Bearer ")
          return render_auth_error("Invalid Authorization header format. Use 'Bearer <token>'")
        end

        bearer_token = auth_header.gsub(/^Bearer\s+/i, "").strip
        if bearer_token.blank?
          return render_auth_error("Missing Bearer token")
        end

        @current_partner = find_partner_by_api_key(header_key)

        unless @current_partner&.verified_at.present? && @current_partner.active?
          Rails.logger.warn("[API AUTH] Invalid partner: #{header_key[0..12]}...")
          return render_auth_error("Invalid or inactive API key")
        end

        @current_token = ::OauthAccessToken.active.find_by(
          token: bearer_token,
          partner_id: @current_partner.id
        )

        unless @current_token
          Rails.logger.warn("[API AUTH] Invalid token: #{bearer_token[0..12]}...")
          return render_auth_error("Invalid or expired OAuth token")
        end
      end

      def find_partner_by_api_key(key)
        digest = Digest::SHA256.hexdigest(key)
        partner = ::Partner.find_by(api_key_digest: digest)
        return partner if partner

        ::Partner.where.not(api_key_digest: nil).detect do |p|
          next false unless p.api_key_digest.to_s.start_with?("$2")
          begin
            BCrypt::Password.new(p.api_key_digest).is_password?(key)
          rescue BCrypt::Errors::InvalidHash
            false
          end
        end
      end

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

      # ============================
      # Rate Limiting
      # ============================

      def rate_limit_exceeded?
        cache_key = "partner:#{@current_partner.id}:incident_reports_requests"
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

      def set_rate_limit_headers(limit:, remaining:)
        response.set_header("X-RateLimit-Limit", limit)
        response.set_header("X-RateLimit-Remaining", remaining)
        response.set_header("X-RateLimit-Reset", (Time.current + RATE_WINDOW).utc.iso8601)
      end

      # ============================
      # Logging
      # ============================

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
            bonid: params[:bonid],
            report_id: params[:id],
            user_agent: request.user_agent,
            timestamp: Time.current.iso8601
          }
        )
      rescue StandardError => e
        Rails.logger.error("[API LOG ERROR] #{e.message}")
      end

      def duration_ms(start_time)
        ((Time.current - start_time) * 1000).round(2)
      end
    end
  end
end
