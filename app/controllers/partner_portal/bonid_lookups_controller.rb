# frozen_string_literal: true

module PartnerPortal
  class BonidLookupsController < PartnerPortal::BaseController
    before_action :authenticate_partner_admin!

    MAX_FAILED_LOOKUPS = 5
    REDIS_EXPIRY_TIME = 10.minutes
    PORTAL_LOOKUP_COST = BigDecimal("0.49")

    # POST /partner_portal/bonid_lookups
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

      # If a raw Ed25519 v2 QR payload was sent, parse it and use it directly.
      # This preserves all fields (v, iss, typ, sub, ts, exp, sig) needed for
      # signature verification by BonidLookupService.
      if payload[:qr_payload].present?
        begin
          qr_parsed = JSON.parse(payload[:qr_payload])
          if qr_parsed["v"].to_i == 2 && qr_parsed["sub"].present? && qr_parsed["sig"].present?
            payload = qr_parsed.merge("partner" => @current_partner&.slug)
            payload[:bonid] = qr_parsed["sub"]
          end
        rescue JSON::ParserError
          # Fall through to normal processing
        end
      end

      bonid     = (payload[:bonid] || payload["sub"])&.strip
      token     = payload[:timestamp] || payload[:verification_token]
      signature = payload[:signature]
      payload[:partner] ||= @current_partner&.slug
      payload["partner"] ||= @current_partner&.slug

      if partner_blocked?
        return render_invalid(:too_many_failures, "Too many failed attempts. Please try again later.", bonid)
      end

      unless bonid.present?
        increment_failure_count
        return render_invalid(:invalid_format, "Missing BonID", bonid)
      end

      # ── Pre-flight credit check (after free daily allowance) ──
      unless can_afford_lookup?
        return render_invalid(
          :insufficient_credits,
          "Kredi ou pa ase. Ou bezwen #{PORTAL_LOOKUP_COST} kredi pou chak rechèch apre #{CreditLedgerEntry::FREE_DAILY_PORTAL_LOOKUPS} gratis pa jou. Rechaje kont ou.",
          bonid
        )
      end

      begin
        service = BonidLookupService.new(payload, nil,
                                         url_helpers: Rails.application.routes.url_helpers,
                                         request: request)
        result = service.perform

        respond_to do |format|
          format.turbo_stream do
            if result.success? && result.visitor && result.status == :visitor_verified
              # Charge BEFORE revealing data — abort if charge fails
              unless charge_portal_lookup!(bonid)
                return render_invalid(:insufficient_credits, "Kredi ou pa ase. Rechaje kont ou.", bonid)
              end

              reset_failure_count
              render turbo_stream: [
                turbo_stream.update("scan_result_frame",
                  partial: "partner_portal/bonid_lookups/scan_result_visitor",
                  locals: { visitor: result.visitor }),
                *credit_badge_streams
              ]
            elsif result.success? && result.submission && result.user
              if result.status == :suffix_lookup_pending_confirmation
                # Don't charge yet — waiting for visual confirmation.
                # Charge happens in #confirm.
                render turbo_stream: turbo_stream.update(
                  "scan_result_frame",
                  partial: "partner_portal/bonid_lookups/scan_result_pending_confirmation",
                  locals: { submission: result.submission, user: result.user }
                )
              else
                # Charge BEFORE revealing data — abort if charge fails
                unless charge_portal_lookup!(result.submission.bonid)
                  return render_invalid(:insufficient_credits, "Kredi ou pa ase. Rechaje kont ou.", bonid)
                end

                reset_failure_count

                # Log the scan
                result.submission.qr_scans.create!(
                  identity_submission: result.submission,
                  partner: @current_partner,
                  verified_by: "Partner",
                  manual: token.blank? && signature.blank?,
                  scanned_at: Time.current,
                  ip_address: request.remote_ip,
                  user_agent: request.user_agent,
                  metadata: { via: token.present? ? "qr" : "manual", partner_id: @current_partner&.id }
                )

                # Auto-check voter eligibility if an election is active
                voter_record = auto_check_voter_eligibility(result.user)

                render turbo_stream: [
                  turbo_stream.update("scan_result_frame",
                    partial: "partner_portal/bonid_lookups/scan_result_valid",
                    locals: {
                      submission: result.submission,
                      user: result.user,
                      partner: @current_partner,
                      voter_record: voter_record
                    }),
                  *credit_badge_streams
                ]
              end
            else
              increment_failure_count
              render_invalid(result.status || :server_error, result.error || "An unexpected error occurred.", bonid)
            end
          end
        end
      rescue StandardError => e
        Rails.logger.error("[PartnerBonidLookup#create] #{e.class}: #{e.message}")
        increment_failure_count
        render turbo_stream: turbo_stream.update(
          "scan_result_frame",
          partial: "partner_portal/bonid_lookups/scan_result_invalid",
          locals: {
            status: :server_error,
            error: "Unexpected server error occurred.",
            bonid: bonid
          }
        ), status: :internal_server_error
      end
    end

    # POST /partner_portal/bonid_lookups/:id/confirm
    def confirm
      submission = IdentitySubmission.find_by(id: params[:id], status: :approved)
      confirmed = params[:confirmed] == "true"

      respond_to do |format|
        format.turbo_stream do
          unless submission
            return render_invalid(:not_found, "Submission not found.", nil)
          end

          unless confirmed
            # ── Log identity mismatch for audit trail & fraud detection ──
            FailedBonidLookup.create!(
              bonid: submission.bonid,
              officer_id: nil,
              reason: "identity_mismatch",
              ip_address: request.remote_ip,
              user_agent: request.user_agent
            )

            PartnerAuditLog.log!(
              @current_partner,
              current_user,
              "identity_mismatch",
              {
                bonid: submission.bonid,
                citizen_id: submission.user_id,
                citizen_name: submission.user&.full_name,
                submission_id: submission.id,
                agent_id: current_user&.id,
                agent_name: current_user&.full_name,
                ip_address: request.remote_ip,
                reported_at: Time.current.iso8601,
                action_taken: "mismatch_reported"
              }
            )

            Rails.logger.warn(
              "🚨 [IDENTITY_MISMATCH] BonID=#{submission.bonid} " \
              "Citizen=#{submission.user&.full_name} (ID:#{submission.user_id}) " \
              "Agent=#{current_user&.full_name} (ID:#{current_user&.id}) " \
              "Partner=#{@current_partner&.name} IP=#{request.remote_ip}"
            )

            return render turbo_stream: turbo_stream.update(
              "scan_result_frame",
              partial: "partner_portal/bonid_lookups/scan_result_mismatch",
              locals: { submission: submission, user: submission.user }
            )
          end

          # Charge BEFORE revealing full details — abort if charge fails
          unless can_afford_lookup?
            return render_invalid(:insufficient_credits, "Kredi ou pa ase. Rechaje kont ou.", submission.bonid)
          end

          unless charge_portal_lookup!(submission.bonid)
            return render_invalid(:insufficient_credits, "Kredi ou pa ase. Rechaje kont ou.", submission.bonid)
          end

          # Confirmed — log the scan
          submission.qr_scans.create!(
            identity_submission: submission,
            partner: @current_partner,
            verified_by: "Partner",
            manual: true,
            scanned_at: Time.current,
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            metadata: { via: "manual", suffix_lookup: true, confirmed_at: Time.current.iso8601 }
          )

          reset_failure_count

          voter_record = auto_check_voter_eligibility(submission.user)

          render turbo_stream: [
            turbo_stream.update("scan_result_frame",
              partial: "partner_portal/bonid_lookups/scan_result_valid",
              locals: {
                submission: submission,
                user: submission.user,
                partner: @current_partner,
                voter_record: voter_record
              }),
            *credit_badge_streams
          ]
        end
      end
    end

    private

    # ── Voter Eligibility ─────────────────────────────────────
    # Auto-register and check voter eligibility if there's an active election.
    # Returns nil if no election is active or on any error (non-blocking).
    def auto_check_voter_eligibility(user)
      return nil unless user&.bonid.present?

      election = BonvoteElection.where(status: "active").order(created_at: :desc).first
      return nil unless election

      VoterEligibilityRecord.register_voter!(election: election, user: user)
    rescue StandardError => e
      Rails.logger.warn("[VoterEligibility] Auto-check failed for #{user&.bonid}: #{e.message}")
      nil
    end

    # ── Credit Enforcement ──────────────────────────────────────

    def can_afford_lookup?
      return true if @current_partner.within_free_portal_allowance?

      @current_partner.credit_balance >= PORTAL_LOOKUP_COST
    end

    # Returns true if charge succeeded, false if it failed (no data should be shown).
    def charge_portal_lookup!(bonid)
      if @current_partner.within_free_portal_allowance?
        @current_partner.log_free_portal_lookup!(
          bonid: bonid,
          ip_address: request.remote_ip
        )
        true
      else
        @current_partner.deduct_credits!(
          amount: PORTAL_LOOKUP_COST,
          endpoint_key: CreditLedgerEntry::PORTAL_LOOKUP_ENDPOINT,
          description: "Portal Lookup: #{bonid}",
          bonid: bonid,
          ip_address: request.remote_ip
        )
        true
      end
    rescue Partner::InsufficientCreditsError
      Rails.logger.warn("[PortalCredits] Race condition: #{@current_partner.slug} insufficient credits for #{bonid}")
      false
    rescue => e
      Rails.logger.error("[PortalCredits] Charge failed for #{@current_partner.slug}: #{e.message}")
      false
    end

    # ── Badge Streams (update free lookups + credit balance after charge) ──

    def credit_badge_streams
      remaining = @current_partner.free_portal_lookups_remaining
      balance = @current_partner.credit_balance

      free_html = if remaining > 0
        <<~HTML
          <div class="wallet-item wallet-item--free">
            <div class="wallet-item-icon"><i class="ri-gift-2-line"></i></div>
            <div class="wallet-item-info">
              <span class="wallet-item-value">#{remaining}</span>
              <span class="wallet-item-label">free today</span>
            </div>
          </div>
        HTML
      else
        <<~HTML
          <div class="wallet-item wallet-item--paid">
            <div class="wallet-item-icon"><i class="ri-copper-coin-line"></i></div>
            <div class="wallet-item-info">
              <span class="wallet-item-value">5</span>
              <span class="wallet-item-label">credits/lookup</span>
            </div>
          </div>
        HTML
      end

      balance_html = <<~HTML
        <div class="wallet-item wallet-item--balance">
          <div class="wallet-item-icon"><i class="ri-money-dollar-circle-line"></i></div>
          <div class="wallet-item-info">
            <span class="wallet-item-value">#{helpers.number_with_delimiter(balance)}</span>
            <span class="wallet-item-label">credits</span>
          </div>
        </div>
      HTML

      [
        turbo_stream.update("free_lookups_badge", free_html),
        turbo_stream.update("credit_balance_badge", balance_html)
      ]
    end

    # ── Render Helpers ──────────────────────────────────────────

    def render_invalid(status, error, bonid)
      render turbo_stream: turbo_stream.update(
        "scan_result_frame",
        partial: "partner_portal/bonid_lookups/scan_result_invalid",
        locals: { status: status, error: error, bonid: bonid }
      )
    end

    # ── Input Parsing ───────────────────────────────────────────

    def parse_input(request)
      raw = request.body.read.presence
      JSON.parse(raw || "{}").deep_symbolize_keys
    rescue JSON::ParserError
      params.permit(:bonid, :timestamp, :signature, :partner, :authenticity_token)
            .to_h
            .symbolize_keys
    end

    # ── Rate Limiting (failed attempts) ─────────────────────────

    def redis
      @redis ||= Redis.new
    end

    def failure_key
      "partner_admin:#{current_partner_admin.id}:failed_lookups"
    end

    def increment_failure_count
      redis.incr(failure_key)
      redis.expire(failure_key, REDIS_EXPIRY_TIME)
    end

    def reset_failure_count
      redis.del(failure_key)
    end

    def partner_blocked?
      redis.get(failure_key).to_i >= MAX_FAILED_LOOKUPS
    end
  end
end
