
# frozen_string_literal: true

module Officers
  class BonidLookupsController < Officers::BaseController
    before_action :authenticate_officer!

    # ✅ Prevent Rails 8 ArgumentError for undefined CSRF callback
    # (This ensures that mobile scanner requests and Turbo streams both work safely)
    if defined?(verify_authenticity_token) && respond_to?(:skip_before_action)
      skip_before_action :verify_authenticity_token,
                         only: :create,
                         if: -> { request.headers["X-Mobile-Scanner"] == "true" },
                         raise: false
    end

    MAX_FAILED_LOOKUPS = 5
    REDIS_EXPIRY_TIME = 10.minutes

    # Enforce unit-based BonID access level before any lookup action.
    # "full"    → complete criminal history and identity profile (DCPJ, POLIFRONT, etc.)
    # "limited" → wanted/criminal status check only (EDUPOL, POLITOUR, DCPR)
    # "standard"→ standard identity verification
    before_action :enforce_bonid_access_level!, only: [:create, :confirm]

    # NOTE: index, failed, manual, and show actions have been moved to partner admin
    # Officers only have create and confirm actions

    def create
      payload = if request.content_type == "application/json"
                  parse_input(request).presence || {}
      elsif params[:bonid_lookup].present?
                  params.require(:bonid_lookup)
                        .permit(:bonid, :timestamp, :signature, :partner,
                                :verification_token, :authenticity_token, :qr_payload)
                        .to_h
                        .symbolize_keys
      else
                  {}
      end

      # Parse raw Ed25519 v2 QR payload if present
      if payload[:qr_payload].present?
        begin
          qr_parsed = JSON.parse(payload[:qr_payload])
          if qr_parsed["v"].to_i == 2 && qr_parsed["sub"].present? && qr_parsed["sig"].present?
            partner_slug = payload[:partner] || current_officer&.partner&.slug
            payload = qr_parsed.merge("partner" => partner_slug)
            payload[:bonid] = qr_parsed["sub"]
          end
        rescue JSON::ParserError
          # Fall through to normal processing
        end
      end

      bonid      = (payload[:bonid] || payload["sub"])&.strip
      token      = payload[:timestamp] || payload[:verification_token]
      signature  = payload[:signature]
      partner    = payload[:partner] || payload["partner"] || current_officer&.partner&.slug

      Rails.logger.info("[BonidLookupsController#create] Received lookup request: bonid=#{bonid}, token=#{token.present?}, signature=#{signature.present?}")

      if officer_blocked?(current_officer)
        return render turbo_stream: turbo_stream.update(
          "scan_result_frame",
          partial: "officers/incident_reports/scan_result_invalid",
          locals: {
            status: :too_many_failures,
            error:  "Too many failed attempts. Officer temporarily blocked.",
            bonid:
          }
        )
      end

      unless bonid.present?
        increment_failure_count(current_officer)
        FailedBonidLookup.create!(
          bonid:,
          verification_token: token,
          signature:,
          officer_id: current_officer.id,
          reason: "Missing BonID",
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        return render turbo_stream: turbo_stream.update(
          "scan_result_frame",
          partial: "officers/incident_reports/scan_result_invalid",
          locals: {
            status: :invalid_format,
            error:  "Missing BonID",
            bonid:
          }
        )
      end

      # Manual lookup (no signature) - use service which handles both full BonID and suffix
      if token.blank? && signature.blank?
        service = BonidLookupService.new(payload, current_officer,
                                         url_helpers: Rails.application.routes.url_helpers,
                                         request:)
        result = service.perform

        return respond_to do |format|
          format.turbo_stream do
            # Handle visitor/tourist lookup (BonTouris)
            if result.success? && result.visitor && result.status == :visitor_verified
              reset_failure_count(current_officer)
              render turbo_stream: turbo_stream.update(
                "scan_result_frame",
                partial: "officers/bonid_lookups/scan_result_visitor",
                locals: { visitor: result.visitor }
              )
            elsif result.success? && result.submission && result.user
              if result.status == :suffix_lookup_pending_confirmation
                render turbo_stream: turbo_stream.update(
                  "scan_result_frame",
                  partial: "officers/bonid_lookups/scan_result_pending_confirmation",
                  locals: { submission: result.submission, user: result.user }
                )
              else
                reset_failure_count(current_officer)
                result.submission.qr_scans.create!(
                  identity_submission: result.submission,
                  officer: current_officer,
                  partner: current_officer&.partner,
                  verified_by: "Officer",
                  manual: true,
                  scanned_at: Time.current,
                  ip_address: request.remote_ip,
                  user_agent: request.user_agent,
                  metadata: { via: "manual", full_bonid_lookup: true }
                )
                # Limited-access units (EDUPOL, POLITOUR, DCPR) only see wanted status
                if @bonid_access_level == "limited"
                  render turbo_stream: turbo_stream.update(
                    "scan_result_frame",
                    partial: "officers/bonid_lookups/scan_result_limited",
                    locals: { submission: result.submission, bonid: result.submission.bonid }
                  )
                else
                  render turbo_stream: turbo_stream.update(
                    "scan_result_frame",
                    partial: "officers/bonid_lookups/scan_result_valid",
                    locals: {
                      submission: result.submission,
                      user: result.user,
                      involvements: result.user.person_involvements.includes(incident_report: :officer).limit(50),
                      partner: result.submission.partner&.slug || "None"
                    }
                  )
                end
              end
            else
              increment_failure_count(current_officer)
              render turbo_stream: turbo_stream.update(
                "scan_result_frame",
                partial: "officers/bonid_lookups/scan_result_invalid",
                locals: { status: result.status, error: result.error, bonid: bonid }
              )
            end
          end
        end
      end

      begin
        service = BonidLookupService.new(payload, current_officer,
                                         url_helpers: Rails.application.routes.url_helpers,
                                         request:)
        result = service.perform

        respond_to do |format|
          format.turbo_stream do
            # Handle visitor/tourist lookup (BonTouris)
            if result.success? && result.visitor && result.status == :visitor_verified
              reset_failure_count(current_officer)
              render turbo_stream: turbo_stream.update(
                "scan_result_frame",
                partial: "officers/bonid_lookups/scan_result_visitor",
                locals: { visitor: result.visitor }
              )
            elsif result.success? && result.submission && result.user
              # Check if this is a suffix lookup requiring confirmation
              if result.status == :suffix_lookup_pending_confirmation
                render turbo_stream: turbo_stream.update(
                  "scan_result_frame",
                  partial: "officers/bonid_lookups/scan_result_pending_confirmation",
                  locals: {
                    submission: result.submission,
                    user: result.user
                  }
                )
              else
                # QR scan or full BonID - already verified
                reset_failure_count(current_officer)
                # Limited-access units only see wanted/criminal status, not full profile
                if @bonid_access_level == "limited"
                  render turbo_stream: turbo_stream.update(
                    "scan_result_frame",
                    partial: "officers/bonid_lookups/scan_result_limited",
                    locals: { submission: result.submission, bonid: result.submission.bonid }
                  )
                else
                  render turbo_stream: turbo_stream.update(
                    "scan_result_frame",
                    partial: "officers/bonid_lookups/scan_result_valid",
                    locals: {
                      submission:    result.submission,
                      user:          result.user,
                      involvements:  result.user.person_involvements
                                           .includes(incident_report: :officer)
                                           .limit(50),
                      partner:       result.submission.partner&.slug || "None"
                    }
                  )
                end
              end
            else
              increment_failure_count(current_officer)
              render turbo_stream: turbo_stream.update(
                "scan_result_frame",
                partial: "officers/bonid_lookups/scan_result_invalid",
                locals: {
                  status: result.status || :server_error,
                  error:  result.error  || "An unexpected error occurred.",
                  bonid:
                }
              )
            end
          end
        end
      rescue StandardError => e
        Rails.logger.error("[BonidLookupsController#create] #{e.class}: #{e.message}")
        increment_failure_count(current_officer)
        render turbo_stream: turbo_stream.update(
          "scan_result_frame",
          partial: "officers/incident_reports/scan_result_invalid",
          locals: {
            status: :server_error,
            error:  "Unexpected server error occurred: #{e.message}",
            bonid:
          }
        ), status: :internal_server_error
      end
    end

    # POST /officers/bonid_lookups/:id/confirm
    # Visual confirmation step after suffix lookup
    def confirm
      submission_id = params[:id]
      confirmed = params[:confirmed] == "true"

      submission = IdentitySubmission.find_by(id: submission_id, status: :approved)

      respond_to do |format|
        format.turbo_stream do
          unless submission
            return render turbo_stream: turbo_stream.update(
              "scan_result_frame",
              partial: "officers/bonid_lookups/scan_result_invalid",
              locals: { status: :not_found, error: "Submission not found or no longer valid.", bonid: nil }
            )
          end

          unless confirmed
            # Officer declined - log as failed match
            FailedBonidLookup.create!(
              bonid: submission.bonid,
              officer_id: current_officer.id,
              reason: "Officer visual verification failed - identity mismatch",
              ip_address: request.remote_ip,
              user_agent: request.user_agent
            )

            return render turbo_stream: turbo_stream.update(
              "scan_result_frame",
              partial: "officers/bonid_lookups/scan_result_mismatch",
              locals: { submission: submission, user: submission.user }
            )
          end

          # Officer confirmed - log successful verification
          submission.qr_scans.create!(
            identity_submission: submission,
            officer: current_officer,
            partner: current_officer&.partner,
            verified_by: "Officer",
            manual: true,
            scanned_at: Time.current,
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            metadata: {
              via: "manual",
              suffix_lookup: true,
              confirmed_at: Time.current.iso8601
            }
          )

          reset_failure_count(current_officer)

          render turbo_stream: turbo_stream.update(
            "scan_result_frame",
            partial: "officers/bonid_lookups/scan_result_confirmed",
            locals: {
              submission: submission,
              user: submission.user,
              involvements: submission.user.person_involvements.includes(incident_report: :officer).limit(50)
            }
          )
        end

        format.html do
          # Fallback for non-turbo requests
          if confirmed && submission
            submission.qr_scans.create!(
              identity_submission: submission,
              officer: current_officer,
              partner: current_officer&.partner,
              verified_by: "Officer",
              manual: true,
              scanned_at: Time.current,
              ip_address: request.remote_ip,
              user_agent: request.user_agent,
              metadata: { via: "manual", suffix_lookup: true, confirmed_at: Time.current.iso8601 }
            )
            reset_failure_count(current_officer)
            redirect_to officers_scan_path, notice: "Identity confirmed successfully"
          elsif submission
            FailedBonidLookup.create!(
              bonid: submission.bonid,
              officer_id: current_officer.id,
              reason: "Officer visual verification failed - identity mismatch",
              ip_address: request.remote_ip,
              user_agent: request.user_agent
            )
            redirect_to officers_scan_path, alert: "Identity mismatch reported"
          else
            redirect_to officers_scan_path, alert: "Submission not found"
          end
        end
      end
    end

    private

    # Sets @bonid_access_level and logs every lookup attempt with the officer's unit + level.
    # "limited" units (EDUPOL, POLITOUR, DCPR) only receive the restricted partial
    # which shows wanted/criminal status without the full identity profile.
    def enforce_bonid_access_level!
      @bonid_access_level = current_officer.bonid_access_level
      Rails.logger.info(
        "[BonidLookup] officer=#{current_officer.badge_id} " \
        "unit=#{current_officer.unit_name} " \
        "access_level=#{@bonid_access_level}"
      )
    end

    def parse_input(request)
      raw = request.body.read.presence
      JSON.parse(raw || "{}").deep_symbolize_keys
    rescue JSON::ParserError
      params.permit(:bonid, :timestamp, :signature, :partner, :authenticity_token)
            .to_h
            .symbolize_keys
    end

    # NOTE: handle_manual_lookup has been replaced by BonidLookupService
    # which now handles both full BonID and suffix lookups

    def redis
      @redis ||= Redis.new
    end

    def failure_key(officer)
      "officer:#{officer.id}:failed_lookups"
    end

    def increment_failure_count(officer)
      redis.incr(failure_key(officer))
      redis.expire(failure_key(officer), REDIS_EXPIRY_TIME)
    end

    def reset_failure_count(officer)
      redis.del(failure_key(officer))
    end

    def officer_blocked?(officer)
      redis.get(failure_key(officer)).to_i >= MAX_FAILED_LOOKUPS
    end
  end
end
