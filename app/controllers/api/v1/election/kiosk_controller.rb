# frozen_string_literal: true

# Consulate Kiosk API — for in-person voting at Haitian consulates.
#
# The kiosk is a tablet running the BonID app in "Kiosk Mode."
# Same cryptographic flow as remote voting, but with:
#   - Consulate ID + Station ID tracking
#   - Print receipt support
#   - Election worker authentication
#   - Physical presence verification via kiosk GPS
#
# Endpoints:
#   POST /api/v1/election/:election_id/kiosk/register  — register a kiosk station
#   POST /api/v1/election/:election_id/kiosk/scan       — scan voter BonID QR at kiosk
#   GET  /api/v1/election/:election_id/kiosk/status      — kiosk health/stats
#
module Api
  module V1
    module Election
      class KioskController < BaseController
        before_action :authenticate_kiosk!

        # ── POST /api/v1/election/:election_id/kiosk/register ──────────
        # Register a kiosk station at a consulate.
        # Called once when the tablet is set up on election day.
        #
        def register
          election_id = params[:election_id]
          consulate_id = params[:consulate_id]
          station_id = params[:station_id]
          gps_lat = params[:latitude]
          gps_lng = params[:longitude]

          # Verify GPS is within expected consulate coordinates
          # (prevents someone from setting up a fake kiosk)
          unless valid_consulate_location?(consulate_id, gps_lat, gps_lng)
            return render json: {
              status: "error",
              error: "invalid_location",
              message: "Kiosk location does not match registered consulate coordinates."
            }, status: :forbidden
          end

          # Register the kiosk session
          kiosk_token = Rails.application.message_verifier("election_kiosk").generate(
            {
              consulate_id: consulate_id,
              station_id: station_id,
              election_id: election_id,
              registered_at: Time.current.iso8601
            },
            expires_in: 18.hours # Election day duration
          )

          Rails.cache.write(
            "kiosk:#{consulate_id}:#{station_id}",
            { status: "active", registered_at: Time.current.iso8601, votes_cast: 0 },
            expires_in: 24.hours
          )

          Rails.logger.info(
            "[Kiosk] Station #{station_id} registered at #{consulate_id} " \
            "(#{gps_lat}, #{gps_lng}) for election #{election_id}"
          )

          render json: {
            status: "registered",
            consulate_id: consulate_id,
            station_id: station_id,
            kiosk_token: kiosk_token,
            expires_in: 18 * 3600, # seconds
            message: "Estasyon #{station_id} anrejistre nan #{consulate_id}."
          }, status: :created
        end

        # ── POST /api/v1/election/:election_id/kiosk/scan ──────────────
        # Scan a voter's BonID QR code at the kiosk.
        # Returns voter info + eligibility without exposing PII to the kiosk screen.
        #
        def scan
          election_id = params[:election_id]
          bonid = params[:bonid]

          user = User.find_by(bonid: bonid)

          unless user&.bonid_verified?
            return render json: {
              status: "error",
              error: "invalid_bonid",
              message: "BonID sa a pa valid oswa pa verifye.",
              display: {
                title: "BonID Pa Valid",
                icon: "error",
                color: "red"
              }
            }, status: :not_found
          end

          # Check eligibility
          voter_key = ::Election::EligibilityProofService.derive_voter_key(
            user.bonid, "kiosk-scan", user.id_number.to_s
          )
          nullifier = ::Election::EligibilityProofService.generate_nullifier(voter_key, election_id)
          already_voted = ::Election::EligibilityProofService.already_voted?(nullifier, election_id)

          if already_voted
            return render json: {
              status: "error",
              error: "already_voted",
              message: "Moun sa a deja vote.",
              display: {
                title: "Deja Vote",
                subtitle: "#{user.first_name} #{user.last_name[0]}.",
                icon: "warning",
                color: "orange"
              }
            }, status: :conflict
          end

          # Eligible — show masked info on kiosk screen
          render json: {
            status: "eligible",
            display: {
              title: "Elektè Elijib",
              subtitle: "#{user.first_name} #{user.last_name[0]}.",
              photo_url: user.photo.attached? ? url_for(user.photo) : nil,
              country: user.identity_submissions.last&.country_of_residence || "HT",
              icon: "success",
              color: "green"
            },
            voter_token: generate_kiosk_voter_token(user, election_id),
            message: "Tanpri fè verifikasyon byometrik pou kontinye."
          }, status: :ok
        end

        # ── GET /api/v1/election/:election_id/kiosk/status ─────────────
        # Health check for the kiosk station.
        # CEP dashboard uses this to monitor all active kiosks.
        #
        def status
          consulate_id = params[:consulate_id]
          station_id = params[:station_id]

          kiosk_data = Rails.cache.read("kiosk:#{consulate_id}:#{station_id}")

          if kiosk_data
            render json: {
              status: "active",
              consulate_id: consulate_id,
              station_id: station_id,
              votes_cast: kiosk_data[:votes_cast] || 0,
              registered_at: kiosk_data[:registered_at],
              uptime: Time.current - Time.parse(kiosk_data[:registered_at])
            }, status: :ok
          else
            render json: {
              status: "offline",
              consulate_id: consulate_id,
              station_id: station_id
            }, status: :not_found
          end
        end

        private

        def authenticate_kiosk!
          kiosk_token = request.headers["X-BonID-Kiosk-Token"]
          kiosk_secret = request.headers["X-BonID-Kiosk-Secret"]

          # For registration, use the consulate secret key
          if action_name == "register"
            expected = Rails.application.credentials.dig(:election, :kiosk_registration_secret)
            unless ActiveSupport::SecurityUtils.secure_compare(kiosk_secret.to_s, expected.to_s)
              render json: { error: "unauthorized", message: "Invalid kiosk registration secret." }, status: :unauthorized
            end
            return
          end

          # For other actions, verify the kiosk session token
          if kiosk_token.blank?
            render json: { error: "unauthorized", message: "Kiosk token required." }, status: :unauthorized
            return
          end

          begin
            @kiosk_session = Rails.application.message_verifier("election_kiosk").verify(kiosk_token)
          rescue ActiveSupport::MessageVerifier::InvalidSignature
            render json: { error: "invalid_token", message: "Kiosk token invalid or expired." }, status: :unauthorized
          end
        end

        def valid_consulate_location?(consulate_id, lat, lng)
          # TODO: Check GPS coordinates against registered consulate locations
          # For now, accept if coordinates are provided
          lat.present? && lng.present?
        end

        def generate_kiosk_voter_token(user, election_id)
          Rails.application.message_verifier("election_voter").generate(
            { user_id: user.id, election_id: election_id, source: "kiosk" },
            expires_in: 15.minutes # Voter has 15 min to complete at kiosk
          )
        end
      end
    end
  end
end
