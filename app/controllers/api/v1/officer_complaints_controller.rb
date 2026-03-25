# frozen_string_literal: true

# app/controllers/api/v1/officer_complaints_controller.rb
#
# Officer Misconduct Summary API — for verified partners (embassies, consulates,
# law firms, OPC investigators) to check an officer's complaint history.
#
# Security model:
#   - Requires dual auth: X-Partner-Api-Key + Bearer token
#   - Scope required: officer:complaints
#   - NEVER exposes: complainant names, narratives, witness info, evidence files
#   - Only exposes: aggregate counts, categories, statuses, risk flag
#   - All access is logged to PartnerApiLog (audit trail)
#
# Endpoints:
#   GET /api/v1/officers/:badge_id/complaints/summary
#
# Response tiers based on partner sector:
#   Tier 1 — basic (all partners): risk_flag, total, has_sustained_complaint
#   Tier 2 — law enforcement / diplomatic: + breakdown by category and status
#   Tier 3 — IGPNH scope only: + per-complaint dates, directorate, resolution notes

module Api
  module V1
    class OfficerComplaintsController < Api::V1::BaseController
      include ResponseSigner

      RATE_LIMIT  = 30          # Requests per window (stricter — sensitive data)
      RATE_WINDOW = 15.minutes
      REQUIRED_SCOPE = "officer:complaints"

      before_action :find_officer
      before_action :check_rate_limit

      # GET /api/v1/officers/:badge_id/complaints/summary
      #
      # Returns complaint summary for a PNH officer identified by badge ID.
      # Response depth depends on partner's access tier.
      #
      # @param badge_id [String] PNH badge ID (e.g. "PNH03456")
      # @return [JSON] Complaint summary (never includes PII of complainants)
      def summary
        start_time = Time.current

        complaints = OfficerComplaint
          .where(accused_officer_id: @officer.id)
          .where.not(status: nil)

        total = complaints.count

        if total == 0
          payload = {
            status:                "ok",
            badge_id:              @officer.badge_id,
            officer_unit:          @officer.unit_name,
            officer_directorate:   @officer.department_directorate,
            complaint_summary: {
              total:                 0,
              has_sustained_complaint: false,
              risk_flag:             "none",
              message:               "No complaints on record for this officer."
            },
            queried_at: Time.current.iso8601
          }
          sign_response(payload)
          log_access(start_time, 200, "No complaints found")
          return render json: payload, status: :ok
        end

        tier   = determine_access_tier
        payload = build_response(complaints, tier, start_time)

        sign_response(payload)
        log_access(start_time, 200, "Summary returned — tier #{tier}")
        render json: payload, status: :ok

      rescue => e
        Rails.logger.error("[OfficerComplaintsController] #{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
        error_payload = {
          status: "error",
          error:  "Internal error",
          code:   500,
          timestamp: Time.current.iso8601
        }
        sign_response(error_payload)
        render json: error_payload, status: :internal_server_error
      end

      private

      def find_officer
        badge_id = params[:badge_id].to_s.strip.upcase
        @officer = Officer.find_by(badge_id: badge_id)

        unless @officer
          payload = {
            status:   "not_found",
            error:    "No officer found with badge ID: #{badge_id}",
            badge_id: badge_id,
            code:     404,
            timestamp: Time.current.iso8601
          }
          sign_response(payload)
          render json: payload, status: :not_found
        end
      end

      def check_rate_limit
        key   = "officer_complaints:#{@partner&.id}:#{request.remote_ip}"
        count = Rails.cache.read(key).to_i
        if count >= RATE_LIMIT
          payload = {
            status: "throttled",
            error:  "Rate limit exceeded. Max #{RATE_LIMIT} requests per 15 minutes.",
            code:   429,
            timestamp: Time.current.iso8601
          }
          sign_response(payload)
          render json: payload, status: :too_many_requests
        else
          Rails.cache.write(key, count + 1, expires_in: RATE_WINDOW)
        end
      end

      # Partner sector → access tier
      # Tier 1: All verified partners (basic aggregate)
      # Tier 2: Diplomatic / law enforcement / legal sectors
      # Tier 3: IGPNH scope (full internal breakdown)
      def determine_access_tier
        scopes = Array(@oauth_token&.scopes).map(&:to_s)
        return 3 if scopes.include?("officer:complaints:full")

        sector = @partner&.sector.to_s.downcase
        return 2 if %w[diplomatic law_enforcement legal government].any? { |s| sector.include?(s) }

        1
      end

      def build_response(complaints, tier, start_time)
        total      = complaints.count
        sustained  = complaints.where(status: %w[closed_sustained disciplinary_action referred_to_prosecutor]).count
        active     = complaints.where(status: %w[under_review investigation_open]).count
        risk_flag  = compute_risk_flag(total, sustained, active)

        payload = {
          status:              "ok",
          badge_id:            @officer.badge_id,
          officer_unit:        @officer.unit_name,
          officer_directorate: @officer.department_directorate,
          complaint_summary: {
            total:                   total,
            has_sustained_complaint: sustained > 0,
            risk_flag:               risk_flag,
            risk_label:              risk_label(risk_flag)
          },
          data_classification: "restricted",
          queried_at:          Time.current.iso8601
        }

        # Tier 2+: category and status breakdowns
        if tier >= 2
          by_category = complaints.group(:allegation_category).count
          by_status   = complaints.group(:status).count.transform_keys do |s|
            status_label_for(s)
          end

          most_recent = complaints.order(occurred_at: :desc).first

          payload[:complaint_summary].merge!(
            by_category:      by_category,
            by_status:        by_status,
            sustained_count:  sustained,
            active_count:     active,
            most_recent_incident: most_recent&.occurred_at&.strftime("%Y-%m")
          )
        end

        # Tier 3: per-complaint breakdown (IGPNH internal use — no PII)
        if tier >= 3
          payload[:complaints] = complaints.order(occurred_at: :desc).map do |c|
            {
              tracking_number:     c.tracking_number,
              allegation_category: c.allegation_category,
              specific_allegation: c.specific_allegation,
              status:              c.status,
              status_label:        status_label_for(c.status),
              occurred_at:         c.occurred_at&.iso8601,
              submitted_at:        c.submitted_at&.iso8601,
              routed_directorate:  c.routed_directorate,
              # Complainant PII deliberately excluded — tracking number only
              # narrative, witnesses, evidence deliberately excluded
            }
          end
        end

        payload
      end

      # Risk scoring logic:
      #   high   → any sustained/disciplinary complaint, OR 3+ total
      #   medium → 1-2 unresolved active complaints
      #   low    → 1-2 complaints, all closed unsustained
      #   none   → no complaints
      def compute_risk_flag(total, sustained, active)
        return "none"   if total == 0
        return "high"   if sustained > 0 || total >= 3
        return "medium" if active > 0
        "low"
      end

      def risk_label(flag)
        {
          "none"   => "No complaints on record",
          "low"    => "Minor — complaints closed without sanction",
          "medium" => "Caution — active complaints under investigation",
          "high"   => "High — sustained complaint or repeated misconduct"
        }[flag] || flag
      end

      def status_label_for(status)
        {
          "submitted"              => "Submitted",
          "under_review"           => "Under Review",
          "investigation_open"     => "Investigation Open",
          "disciplinary_action"    => "Disciplinary Action Taken",
          "referred_to_prosecutor" => "Referred to Prosecutor",
          "closed_sustained"       => "Closed — Sustained",
          "closed_unsustained"     => "Closed — Unsustained"
        }[status.to_s] || status.to_s.humanize
      end

      def log_access(start_time, status_code, message)
        duration = ((Time.current - start_time) * 1000).round(2)
        Rails.logger.info(
          "[OfficerComplaintsController] badge=#{@officer&.badge_id} " \
          "partner=#{@partner&.name} status=#{status_code} " \
          "duration_ms=#{duration} msg=#{message}"
        )
      end
    end
  end
end
