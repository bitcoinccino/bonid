# frozen_string_literal: true

# Ajan::BonidLookupsController
# ============================
# Agent-facing BonID verification. Mirrors PartnerPortal::BonidLookupsController
# but authenticates via the :agent scope and attributes scans + ledger entries
# to the agent's partner.
#
# Reuses partner_portal result partials (scan_result_valid, scan_result_invalid,
# scan_result_visitor, scan_result_pending_confirmation, scan_result_mismatch),
# plus BonidLookupService and VoterEligibilityRecord.register_voter!.
module Ajan
  class BonidLookupsController < Ajan::ApplicationController
    MAX_FAILED_LOOKUPS = 5
    REDIS_EXPIRY_TIME  = 10.minutes
    PORTAL_LOOKUP_COST = BigDecimal("0.49")

    # POST /ajan/bonid_lookups
    def create
      payload = parse_payload

      if payload[:qr_payload].present?
        begin
          qr_parsed = JSON.parse(payload[:qr_payload])
          if qr_parsed["v"].to_i == 2 && qr_parsed["sub"].present? && qr_parsed["sig"].present?
            payload = qr_parsed.merge("partner" => current_partner&.slug)
            payload[:bonid] = qr_parsed["sub"]
          end
        rescue JSON::ParserError
          # fall through
        end
      end

      bonid              = (payload[:bonid] || payload["sub"])&.strip
      token              = payload[:timestamp] || payload[:verification_token]
      signature          = payload[:signature]
      payload[:partner] ||= current_partner&.slug
      payload["partner"] ||= current_partner&.slug

      if agent_blocked?
        return render_invalid(:too_many_failures, "Twòp echèk. Tanpri eseye pita.", bonid)
      end

      unless bonid.present?
        increment_failure_count
        return render_invalid(:invalid_format, "BonID manke", bonid)
      end

      unless can_afford_lookup?
        return render_invalid(
          :insufficient_credits,
          "Kredi patnè a pa ase. Kontakte administratè a.",
          bonid
        )
      end

      service = BonidLookupService.new(payload, nil,
                                        url_helpers: Rails.application.routes.url_helpers,
                                        request: request)
      result  = service.perform

      respond_to do |format|
        format.turbo_stream do
          if result.success? && result.visitor && result.status == :visitor_verified
            unless charge_portal_lookup!(bonid)
              return render_invalid(:insufficient_credits, "Kredi patnè a pa ase.", bonid)
            end

            reset_failure_count
            render turbo_stream: turbo_stream.update(
              "scan_result_frame",
              partial: "partner_portal/bonid_lookups/scan_result_visitor",
              locals: { visitor: result.visitor }
            )

          elsif result.success? && result.submission && result.user
            if result.status == :suffix_lookup_pending_confirmation
              # Pass the ajan-scoped confirm URL so the Confirm Identity /
              # Not a Match buttons POST back into the ajan namespace where
              # the agent is authenticated.
              render turbo_stream: turbo_stream.update(
                "scan_result_frame",
                partial: "partner_portal/bonid_lookups/scan_result_pending_confirmation",
                locals: {
                  submission: result.submission,
                  user:       result.user,
                  confirm_url: confirm_ajan_bonid_lookup_path(result.submission.id)
                }
              )
            else
              unless charge_portal_lookup!(result.submission.bonid)
                return render_invalid(:insufficient_credits, "Kredi patnè a pa ase.", bonid)
              end

              reset_failure_count

              result.submission.qr_scans.create!(
                identity_submission: result.submission,
                partner: current_partner,
                verified_by: "Ajan",
                manual: token.blank? && signature.blank?,
                scanned_at: Time.current,
                ip_address: request.remote_ip,
                user_agent: request.user_agent,
                metadata: {
                  via: token.present? ? "qr" : "manual",
                  partner_id: current_partner&.id,
                  agent_id: current_agent&.id
                }
              )

              voter_record = auto_check_voter_eligibility(result.user)

              render turbo_stream: turbo_stream.update(
                "scan_result_frame",
                partial: "partner_portal/bonid_lookups/scan_result_valid",
                locals: {
                  submission: result.submission,
                  user: result.user,
                  partner: current_partner,
                  voter_record: voter_record
                }
              )
            end
          else
            increment_failure_count
            render_invalid(result.status || :server_error, result.error || "Erè pandan rechèch la.", bonid)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error("[Ajan::BonidLookup#create] #{e.class}: #{e.message}")
      increment_failure_count
      render turbo_stream: turbo_stream.update(
        "scan_result_frame",
        partial: "partner_portal/bonid_lookups/scan_result_invalid",
        locals: { status: :server_error, error: "Erè sèvè.", bonid: nil }
      ), status: :internal_server_error
    end

    # POST /ajan/bonid_lookups/:id/confirm
    def confirm
      submission = IdentitySubmission.find_by(id: params[:id], status: :approved)
      confirmed  = params[:confirmed] == "true"

      respond_to do |format|
        format.turbo_stream do
          unless submission
            return render_invalid(:not_found, "Pa jwenn soumisyon an.", nil)
          end

          unless confirmed
            FailedBonidLookup.create!(
              bonid: submission.bonid,
              officer_id: nil,
              reason: "identity_mismatch",
              ip_address: request.remote_ip,
              user_agent: request.user_agent
            )

            PartnerAuditLog.log!(
              current_partner,
              current_agent,
              "identity_mismatch",
              {
                bonid: submission.bonid,
                citizen_id: submission.user_id,
                citizen_name: submission.user&.full_name,
                submission_id: submission.id,
                agent_id: current_agent&.id,
                agent_name: current_agent&.full_name,
                ip_address: request.remote_ip,
                reported_at: Time.current.iso8601,
                action_taken: "mismatch_reported"
              }
            )

            return render turbo_stream: turbo_stream.update(
              "scan_result_frame",
              partial: "partner_portal/bonid_lookups/scan_result_mismatch",
              locals: { submission: submission, user: submission.user }
            )
          end

          unless charge_portal_lookup!(submission.bonid)
            return render_invalid(:insufficient_credits, "Kredi patnè a pa ase.", submission.bonid)
          end

          submission.qr_scans.create!(
            identity_submission: submission,
            partner: current_partner,
            verified_by: "Ajan",
            manual: true,
            scanned_at: Time.current,
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            metadata: {
              via: "manual",
              suffix_lookup: true,
              confirmed_at: Time.current.iso8601,
              agent_id: current_agent&.id
            }
          )

          reset_failure_count
          voter_record = auto_check_voter_eligibility(submission.user)

          render turbo_stream: turbo_stream.update(
            "scan_result_frame",
            partial: "partner_portal/bonid_lookups/scan_result_valid",
            locals: {
              submission: submission,
              user: submission.user,
              partner: current_partner,
              voter_record: voter_record
            }
          )
        end
      end
    end

    private

    def parse_payload
      if request.content_type == "application/json"
        raw = request.body.read.presence
        (JSON.parse(raw || "{}").deep_symbolize_keys rescue {})
      elsif params[:bonid_lookup].present?
        params.require(:bonid_lookup)
              .permit(:bonid, :timestamp, :signature, :partner,
                      :verification_token, :authenticity_token, :qr_payload)
              .to_h
              .symbolize_keys
      else
        {}
      end
    end

    # Auto-register + return voter eligibility when an active election is running.
    # Non-blocking: any error is logged and the result partial renders without
    # voter detail.
    def auto_check_voter_eligibility(user)
      return nil unless user&.bonid.present?

      election = BonvoteElection.where(status: "active").order(created_at: :desc).first
      return nil unless election

      VoterEligibilityRecord.register_voter!(election: election, user: user)
    rescue StandardError => e
      Rails.logger.warn("[Ajan::VoterEligibility] Auto-check failed for #{user&.bonid}: #{e.message}")
      nil
    end

    def can_afford_lookup?
      return true if current_partner.within_free_portal_allowance?

      current_partner.credit_balance >= PORTAL_LOOKUP_COST
    end

    def charge_portal_lookup!(bonid)
      if current_partner.within_free_portal_allowance?
        current_partner.log_free_portal_lookup!(bonid: bonid, ip_address: request.remote_ip)
        true
      else
        current_partner.deduct_credits!(
          amount: PORTAL_LOOKUP_COST,
          endpoint_key: CreditLedgerEntry::PORTAL_LOOKUP_ENDPOINT,
          description: "Ajan Lookup: #{bonid}",
          bonid: bonid,
          ip_address: request.remote_ip
        )
        true
      end
    rescue Partner::InsufficientCreditsError
      false
    rescue StandardError => e
      Rails.logger.error("[Ajan::PortalCredits] Charge failed for #{current_partner&.slug}: #{e.message}")
      false
    end

    def render_invalid(status, error, bonid)
      render turbo_stream: turbo_stream.update(
        "scan_result_frame",
        partial: "partner_portal/bonid_lookups/scan_result_invalid",
        locals: { status: status, error: error, bonid: bonid }
      )
    end

    # Rate limiting (failed attempts) — keyed per agent.
    def redis
      @redis ||= Redis.new
    rescue StandardError
      nil
    end

    def failure_key
      "ajan:#{current_agent&.id}:failed_lookups"
    end

    def increment_failure_count
      return unless redis
      redis.incr(failure_key)
      redis.expire(failure_key, REDIS_EXPIRY_TIME)
    end

    def reset_failure_count
      redis&.del(failure_key)
    end

    def agent_blocked?
      return false unless redis
      redis.get(failure_key).to_i >= MAX_FAILED_LOOKUPS
    end
  end
end
