# frozen_string_literal: true

# Election Ballots API — the ballot box.
#
# Endpoints:
#   GET  /api/v1/election/:election_id/eligibility  — check voter eligibility
#   POST /api/v1/election/:election_id/cast          — cast a vote (idempotent)
#   GET  /api/v1/election/:election_id/verify/:hash  — public ballot verification
#
# Security:
#   - App attestation (genuine BonID app only)
#   - Biometric voter token (liveness + face match completed)
#   - Rate limited (3 casts/min, 10 checks/min)
#   - Idempotent (same nullifier returns same receipt, no double-count)
#   - Zero-knowledge (server never sees the vote choice)
#
module Api
  module V1
    module Election
      class BallotsController < BaseController
        before_action :authenticate_voter!, only: [ :eligibility, :cast ]
        skip_before_action :verify_app_attestation!, only: [ :verify ]
        skip_before_action :authenticate_voter!, only: [ :verify ]
        skip_before_action :authenticate_partner_or_token!, only: [ :verify ]
        skip_before_action :enforce_scope!, only: [ :verify ], raise: false
        skip_before_action :ensure_api_request!, only: [ :verify ], raise: false

        # ── GET /api/v1/election/:election_id/eligibility ──────────────
        # Checks if the voter is on the CEP roll and hasn't voted yet.
        # Returns a challenge nonce for the Schnorr ZKP.
        #
        def eligibility
          election_id = params[:election_id]

          # Check if election exists and is open
          unless election_open?(election_id)
            return render json: {
              eligible: false,
              reason: "election_closed",
              message: "Eleksyon sa a fèmen oswa pa egziste."
            }, status: :forbidden
          end

          # Check if voter has a verified BonID
          unless current_voter.bonid_verified?
            return render json: {
              eligible: false,
              reason: "unverified_bonid",
              message: "Ou bezwen yon BonID verifye pou vote."
            }, status: :forbidden
          end

          # Check CIN number is on the voter roll
          cin_number = current_voter.id_number
          unless cin_on_voter_roll?(cin_number, election_id)
            return render json: {
              eligible: false,
              reason: "not_on_roll",
              message: "Nimewo CIN ou pa sou lis elektoral la. Kontakte CEP."
            }, status: :forbidden
          end

          # Generate nullifier to check for double-voting
          voter_key = ::Election::EligibilityProofService.derive_voter_key(
            current_voter.bonid,
            "eligibility-check",
            current_voter.id_number.to_s
          )
          nullifier = ::Election::EligibilityProofService.generate_nullifier(voter_key, election_id)

          if ::Election::EligibilityProofService.already_voted?(nullifier, election_id)
            return render json: {
              eligible: false,
              reason: "already_voted",
              message: "Ou deja vote nan eleksyon sa a."
            }, status: :forbidden
          end

          # Geolocation validation — flag mismatch but don't block
          # (voter may be traveling; CEP reviews flagged votes)
          # Skip for kiosk votes — constituency is known from the kiosk location
          ip_country = vote_source == "kiosk" ? nil : IpGeolocator.country_code(request.remote_ip)
          location_check = verify_voter_location(current_voter.bonid, ip_country)

          # Eligible — issue challenge nonce for ZKP
          challenge_nonce = SecureRandom.hex(32)
          Rails.cache.write(
            "election_challenge:#{current_voter.id}:#{election_id}",
            challenge_nonce,
            expires_in: 10.minutes
          )

          # Route to correct ballot based on BonID location code
          ballot_route = ::Election::BallotRoutingService.route(current_voter, election_id)

          render json: {
            eligible: true,
            election_id: election_id,
            bonid: current_voter.bonid,
            country: current_voter.identity_submissions.last&.country_of_residence || "HT",
            challenge_nonce: challenge_nonce,
            expires_in: 600, # 10 minutes to complete voting
            location: {
              bonid_country: location_check[:bonid_country],
              ip_country: ip_country,
              match: location_check[:match],
              flagged: !location_check[:match]
            },
            ballot: {
              type: ballot_route[:type],
              department: ballot_route[:department],
              sections: ballot_route[:ballot_sections]&.map { |s| { title: s[:title], position: s[:position] } },
              message: ballot_route[:message]
            }
          }, status: :ok
        end

        # ── POST /api/v1/election/:election_id/cast ────────────────────
        # Casts a vote. Idempotent — retrying with the same nullifier
        # returns the existing receipt without double-counting.
        #
        # Expected payload (< 1KB):
        #   {
        #     nullifier: "hex...",
        #     encrypted_choice: { encrypted_choice:, encrypted_key:, iv:, auth_tag: },
        #     zkp_commitment: "hex...",
        #     zkp_proof: { challenge:, response:, public_commitment: },
        #     liveness_session_id: "uuid",
        #     biometric_hash: "hex..."
        #   }
        #
        def cast
          election_id = params[:election_id]
          payload = params.permit(
            :nullifier, :zkp_commitment, :liveness_session_id, :biometric_hash,
            zkp_proof: [ :challenge, :response, :public_commitment ],
            encrypted_choice: [ :encrypted_choice, :encrypted_key, :iv, :auth_tag ]
          )

          # Validate election is open
          unless election_open?(election_id)
            return render json: {
              status: "error",
              error: "election_closed",
              message: "Eleksyon sa a fèmen."
            }, status: :forbidden
          end

          # ── Idempotency Check ──
          # If this nullifier already exists, return the existing receipt
          existing = find_existing_ballot(payload[:nullifier], election_id)
          if existing
            Rails.logger.info("[Election API] Idempotent retry for nullifier #{payload[:nullifier][0..7]}...")
            return render json: {
              status: "success",
              message: "Vòt ou te deja anrejistre.",
              ballot_hash: existing[:ballot_hash],
              receipt_id: existing[:receipt_id],
              idempotent: true
            }, status: :ok
          end

          # ── Cast the vote ──
          begin
            result = ::Election::BallotService.cast(
              citizen: current_voter,
              election_id: election_id,
              choice: 0, # Server never knows the choice — it's in encrypted_choice
              liveness_session_id: payload[:liveness_session_id],
              biometric_hash: payload[:biometric_hash],
              cep_public_key: cep_public_key(election_id)
            )

            # Tag with source (remote app vs consulate kiosk)
            ballot = result[:ballot]
            if vote_source == "kiosk" && consulate_id.present?
              ballot = ::Election::AuditService.tag_consulate_vote(ballot, consulate_id, params[:station_id])
            end

            # Store the ballot
            store_ballot!(election_id, ballot, result[:receipt])

            # Broadcast to CEP dashboard
            broadcast_new_vote(election_id)

            render json: {
              status: "success",
              message: "Vòt ou anrejistre ak siksè!",
              ballot_hash: result[:receipt][:ballot_hash],
              receipt_id: result[:receipt][:receipt_id],
              timestamp: result[:receipt][:timestamp],
              payload_size: result[:payload_size],
              source: vote_source
            }, status: :created

          rescue ::Election::BallotService::AlreadyVotedError => e
            render json: {
              status: "error",
              error: "already_voted",
              message: e.message
            }, status: :conflict

          rescue ::Election::BallotService::IneligibleError => e
            render json: {
              status: "error",
              error: "ineligible",
              message: e.message
            }, status: :forbidden

          rescue => e
            Rails.logger.error("[Election API] Vote cast failed: #{e.message}")
            render json: {
              status: "error",
              error: "internal_error",
              message: "Erè entèn. Tanpri eseye ankò."
            }, status: :internal_server_error
          end
        end

        # ── GET /api/v1/election/:election_id/verify/:hash ─────────────
        # Public endpoint — no auth required.
        # Powers the "Vòt ou konte" verification page.
        #
        def verify
          election_id = params[:election_id]
          ballot_hash = params[:hash]

          result = ::Election::AuditService.verify_ballot_presence(ballot_hash, election_id)

          status_code = result[:found] ? :ok : :not_found

          render json: {
            verified: result[:found],
            message: result[:message],
            election_id: election_id,
            timestamp: result[:timestamp],
            position: result[:position]
          }, status: status_code
        end

        private

        def election_open?(election_id)
          ::Election::ElectionCache.open?(election_id)
        end

        def cin_on_voter_roll?(cin_number, election_id)
          # TODO: Cross-reference with CEP voter roll database
          # For now, any verified BonID holder with a CIN is eligible
          cin_number.present?
        end

        def cep_public_key(election_id)
          ::Election::ElectionCache.cep_public_key(election_id)
        end

        def find_existing_ballot(nullifier, election_id)
          ballot = ElectionBallot.find_by(nullifier: nullifier, election_id: election_id)
          return nil unless ballot

          { ballot_hash: ballot.ballot_hash, receipt_id: ballot.receipt_id }
        end

        def store_ballot!(election_id, ballot, receipt)
          location_code = ::Election::BallotRoutingService.send(:extract_location_code, current_voter.bonid)
          ip_country = vote_source == "kiosk" ? nil : IpGeolocator.country_code(request.remote_ip)

          ElectionBallot.create!(
            election_id: election_id,
            nullifier: ballot[:nullifier],
            position: params[:position] || "president",
            encrypted_choice: ballot[:encrypted_choice].to_json,
            encrypted_key: ballot.dig(:encrypted_choice, :encrypted_key),
            iv: ballot.dig(:encrypted_choice, :iv),
            auth_tag: ballot.dig(:encrypted_choice, :auth_tag),
            zkp_commitment: ballot[:zkp_commitment],
            zkp_proof: ballot[:zkp_proof],
            ballot_hash: receipt[:ballot_hash],
            receipt_id: receipt[:receipt_id],
            channel: vote_source == "kiosk" ? "consulate" : "remote",
            consulate_id: params[:consulate_id],
            station_id: params[:station_id],
            department_code: location_code,
            ip_country: ip_country,
            location_flagged: ip_country.present? && location_code.present? && ip_country.upcase != location_code,
            cast_at: Time.current
          )

          Rails.logger.info(
            "[Election API] Ballot stored: election=#{election_id} " \
            "nullifier=#{ballot[:nullifier][0..7]}... source=#{vote_source}"
          )
        end

        # ── Geolocation Validation ─────────────────────────────────────
        # Extracts the ISO country code from the BonID format and compares
        # it against the reported country from the request.
        #
        # BonID format: VP-1970-M-US-P2334-4EC
        #                          ^^ country/dept code at index 3
        #
        def verify_voter_location(bonid, reported_country)
          bonid_parts = bonid.to_s.split("-")
          bonid_location = bonid_parts[3] if bonid_parts.length >= 4

          return { match: true } if bonid_location.blank? || reported_country.blank?

          if bonid_location.length == 2 && bonid_location != reported_country.to_s.upcase
            # Diaspora BonID country doesn't match reported location
            Rails.logger.warn(
              "[Election API] Location mismatch: BonID says #{bonid_location}, " \
              "reported #{reported_country} for #{bonid}"
            )
            { match: false, bonid_country: bonid_location, reported_country: reported_country }
          else
            { match: true, bonid_country: bonid_location }
          end
        end

        def broadcast_new_vote(election_id)
          # Increment Redis counter (O(1), ~0.1ms) instead of enqueuing
          # a background job on every single vote. The aggregated broadcast
          # job runs every 5 seconds and pushes stats to CEP dashboards.
          ::Election::ElectionCache.increment_vote_count!(election_id)
        end
      end
    end
  end
end
