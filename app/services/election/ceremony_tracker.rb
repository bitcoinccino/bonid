# frozen_string_literal: true

# Multi-Sig Ceremony Tracker — real-time quorum progress visualization.
#
# Provides a structured timeline of the 5-of-9 decryption ceremony:
#   - Which roles have signed and when
#   - Which roles are still pending
#   - How long the ceremony has been running
#   - Liveness verification status per signatory
#   - Estimated time to quorum (based on signing pace)
#
# This service is read-only — it queries ElectionSignature records
# created by MultiSigService and shapes them for the dashboard.
#
# Usage:
#   CeremonyTracker.progress(election_id)
#   CeremonyTracker.timeline(election_id)
#
module Election
  class CeremonyTracker
    QUORUM_REQUIRED = MultiSigService::QUORUM_REQUIRED
    TOTAL_SIGNATORIES = MultiSigService::TOTAL_SIGNATORIES

    # ── Quorum Progress Bar ──────────────────────────────────────
    # Returns structured data for rendering a visual progress bar:
    #   "3 of 5 Keys Collected"

    def self.progress(election_id)
      signatures = load_signatures(election_id)
      signed_roles = signatures.map { |s| s[:role] }
      pending_roles = MultiSigService::SIGNATORY_ROLES - signed_roles

      ceremony_started_at = signatures.first&.dig(:signed_at)
      last_signed_at = signatures.last&.dig(:signed_at)

      {
        signed: signatures.size,
        required: QUORUM_REQUIRED,
        total: TOTAL_SIGNATORIES,
        quorum_met: signatures.size >= QUORUM_REQUIRED,
        percentage: ((signatures.size.to_f / QUORUM_REQUIRED) * 100).clamp(0, 100).round,

        # Visual status for the progress bar
        status: ceremony_status(signatures.size),
        status_label: ceremony_status_label(signatures.size),

        # Who signed
        signatories: signatures.map do |s|
          {
            role: s[:role],
            role_label: MultiSigService.role_label(s[:role]),
            name: s[:name],
            signed_at: s[:signed_at],
            liveness_verified: s[:liveness_verified]
          }
        end,

        # Who hasn't signed yet
        pending_roles: pending_roles.map do |role|
          {
            role: role,
            role_label: MultiSigService.role_label(role)
          }
        end,

        # Timing
        ceremony_started_at: ceremony_started_at,
        last_signature_at: last_signed_at,
        ceremony_duration_seconds: ceremony_duration(ceremony_started_at),
        estimated_remaining_seconds: estimate_remaining(signatures.size, ceremony_started_at, last_signed_at)
      }
    end

    # ── Signing Timeline ─────────────────────────────────────────
    # Ordered list of all signing events for the ceremony log.

    def self.timeline(election_id)
      signatures = load_signatures(election_id)

      events = signatures.each_with_index.map do |sig, idx|
        prev_time = idx > 0 ? Time.parse(signatures[idx - 1][:signed_at]) : nil
        current_time = Time.parse(sig[:signed_at])
        gap = prev_time ? (current_time - prev_time).round : 0

        {
          sequence: idx + 1,
          role: sig[:role],
          role_label: MultiSigService.role_label(sig[:role]),
          name: sig[:name],
          signed_at: sig[:signed_at],
          liveness_verified: sig[:liveness_verified],
          gap_from_previous_seconds: gap,
          quorum_state: "#{idx + 1}/#{QUORUM_REQUIRED}"
        }
      end

      {
        election_id: election_id,
        events: events,
        total_signatures: signatures.size,
        quorum_met: signatures.size >= QUORUM_REQUIRED,
        ceremony_complete: signatures.size >= QUORUM_REQUIRED
      }
    end

    # ── Broadcast-Ready Payload ──────────────────────────────────
    # Compact payload designed for ActionCable real-time updates.

    def self.broadcast_payload(election_id)
      prog = progress(election_id)

      {
        type: "ceremony_progress",
        signed: prog[:signed],
        required: prog[:required],
        percentage: prog[:percentage],
        status: prog[:status],
        status_label: prog[:status_label],
        quorum_met: prog[:quorum_met],
        latest_signatory: prog[:signatories].last,
        pending_count: prog[:pending_roles].size,
        duration_seconds: prog[:ceremony_duration_seconds]
      }
    end

    private

    def self.load_signatures(election_id)
      ElectionSignature.where(election_id: election_id).order(:signed_at).map do |s|
        {
          role: s.role,
          name: s.signatory_name,
          signed_at: s.signed_at.iso8601,
          liveness_verified: s.liveness_verified
        }
      end
    rescue NameError
      []
    end

    def self.ceremony_status(count)
      case count
      when 0 then "waiting"
      when 1..2 then "early"
      when 3..4 then "approaching"
      else "complete"
      end
    end

    def self.ceremony_status_label(count)
      case count
      when 0 then "Ap tann premye siyati a..." # Waiting for first signature...
      when 1..2 then "#{count}/#{QUORUM_REQUIRED} kle kolekte" # X/5 keys collected
      when 3..4 then "Prèske rive — #{count}/#{QUORUM_REQUIRED} kle kolekte" # Almost there
      else "Kowòm atenn! Rezilta yo ap dechifre." # Quorum reached! Results decrypting.
      end
    end

    def self.ceremony_duration(started_at)
      return nil unless started_at
      (Time.current - Time.parse(started_at)).round
    rescue
      nil
    end

    def self.estimate_remaining(count, started_at, last_signed_at)
      return nil if count.zero? || count >= QUORUM_REQUIRED || started_at.nil?

      elapsed = Time.parse(last_signed_at) - Time.parse(started_at)
      return nil if elapsed <= 0

      avg_per_signature = elapsed / count
      remaining_signatures = QUORUM_REQUIRED - count
      (avg_per_signature * remaining_signatures).round
    rescue
      nil
    end
  end
end
