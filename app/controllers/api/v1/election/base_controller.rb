# frozen_string_literal: true

# Base controller for Election API endpoints.
#
# Security layers:
#   1. App attestation — verifies the request comes from a genuine BonID app instance
#   2. Rate limiting — prevents brute-force and bot attacks
#   3. Idempotency — duplicate requests return the same result (safe retries on bad connections)
#   4. Zero-knowledge — the API never sees the vote choice, only encrypted payloads
#
module Api
  module V1
    module Election
      class BaseController < Api::V1::BaseController
        before_action :verify_app_attestation!
        before_action :enforce_election_rate_limit!

        private

        # ── App Attestation (Security Handshake) ─────────────────────────
        # Verifies the request comes from a genuine BonID app, not a spoofed client.
        #
        # The handshake:
        #   1. App generates a nonce: HMAC-SHA256(app_secret, timestamp + device_id)
        #   2. App sends: X-BonID-Attestation: <nonce>
        #                 X-BonID-Timestamp: <unix_timestamp>
        #                 X-BonID-Device: <device_fingerprint>
        #   3. Server recomputes the HMAC and compares
        #   4. Timestamp must be within 5 minutes (prevents replay attacks)
        #
        def verify_app_attestation!
          attestation = request.headers["X-BonID-Attestation"]
          timestamp   = request.headers["X-BonID-Timestamp"]
          device_id   = request.headers["X-BonID-Device"]

          if attestation.blank? || timestamp.blank?
            render json: {
              error: "missing_attestation",
              message: "App attestation headers required. See API docs."
            }, status: :unauthorized
            return
          end

          # Check timestamp freshness (5 minute window)
          request_time = Time.at(timestamp.to_i) rescue nil
          if request_time.nil? || (Time.current - request_time).abs > 5.minutes
            render json: {
              error: "expired_attestation",
              message: "Attestation timestamp expired. Resync device clock."
            }, status: :unauthorized
            return
          end

          # Recompute and compare HMAC
          app_secret = Rails.application.credentials.dig(:election, :app_attestation_secret)
          expected = OpenSSL::HMAC.hexdigest("SHA256", app_secret.to_s, "#{timestamp}#{device_id}")

          unless ActiveSupport::SecurityUtils.secure_compare(attestation, expected)
            Rails.logger.warn("[Election API] Invalid attestation from #{request.remote_ip} device=#{device_id}")
            render json: {
              error: "invalid_attestation",
              message: "App attestation failed. Ensure you are using an official BonID app."
            }, status: :forbidden
          end
        end

        # ── Rate Limiting ────────────────────────────────────────────────
        # Election endpoints have stricter rate limits than regular API:
        #   - Eligibility check: 10/minute per user
        #   - Vote cast: 3/minute per user (retries allowed, nullifier prevents double-count)
        #   - Verify: 60/minute per IP (public endpoint)
        #
        def enforce_election_rate_limit!
          key = "election_rate:#{current_voter&.id || request.remote_ip}:#{controller_name}:#{action_name}"
          limit = rate_limit_for_action

          count = Rails.cache.increment(key, 1, expires_in: 1.minute)

          if count.to_i > limit
            render json: {
              error: "rate_limited",
              message: "Twòp demann. Tanpri tann yon minit epi eseye ankò.",
              retry_after: 60
            }, status: :too_many_requests
          end
        end

        def rate_limit_for_action
          case action_name
          when "cast"         then 3
          when "eligibility"  then 10
          when "verify"       then 60
          else 30
          end
        end

        # ── Voter Authentication ─────────────────────────────────────────
        # Uses BonID biometric session token (issued after liveness + face match)
        #
        def authenticate_voter!
          token = request.headers["X-BonID-Voter-Token"]

          if token.blank?
            render json: { error: "unauthorized", message: "Voter authentication required." }, status: :unauthorized
            return
          end

          # Verify the biometric session token
          @current_voter = verify_voter_token(token)

          unless @current_voter
            render json: { error: "invalid_token", message: "Voter token invalid or expired." }, status: :unauthorized
          end
        end

        def current_voter
          @current_voter
        end

        def verify_voter_token(token)
          # Decode the signed token to extract user_id + liveness_session_id
          payload = Rails.application.message_verifier("election_voter").verify(token)
          User.find_by(id: payload[:user_id])
        rescue ActiveSupport::MessageVerifier::InvalidSignature
          nil
        end

        # ── Source Tracking ──────────────────────────────────────────────
        def vote_source
          request.headers["X-BonID-Source"] || "remote"
        end

        def consulate_id
          request.headers["X-BonID-Consulate"] || params[:consulate_id]
        end
      end
    end
  end
end
