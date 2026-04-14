# frozen_string_literal: true

# Citizens::Election::VoteController — Multi-step voting wizard.
#
# Flow:
#   1. eligibility (GET)  → Check BonID, election open, not already voted
#   2. begin      (POST)  → Liveness verification, generate challenge nonce
#   3. ballot     (GET)   → Show candidates by section (immersive)
#   4. cast       (POST)  → Receive encrypted vote, store ballot
#   5. receipt    (GET)   → Show receipt with hash + QR code
#
# Security:
#   - Verified BonID required
#   - Liveness verification before ballot access
#   - Vote encrypted client-side (server never sees the choice)
#   - Nullifier prevents double-voting (idempotent)
#   - Challenge nonce expires after 10 minutes
#
module Citizens
  module Election
    class VoteController < BaseController
      before_action :require_verified_bonid!
      before_action :require_active_election!, only: [:begin, :ballot, :cast]
      before_action :enable_immersive_form, only: [:ballot, :cast, :receipt]

      # ── Step 1: Eligibility Check ──────────────────────────────
      # Shows election info + checks if citizen can vote.
      # If no election is open, shows a "no election" state instead of redirecting.
      def eligibility
        @election = active_election
        @upcoming_election = BonvoteElection.where(status: "draft").order(election_date: :asc).first unless @election

        # No open election — render the page with a message, don't redirect
        unless @election
          render :eligibility
          return
        end

        # Check CIN on voter roll
        cin_number = current_citizen.id_number
        @has_cin = cin_number.present?

        # Generate nullifier to check double-voting
        if @has_cin
          voter_key = ::Election::EligibilityProofService.derive_voter_key(
            current_citizen.bonid,
            "eligibility-check",
            cin_number.to_s
          )
          nullifier = ::Election::EligibilityProofService.generate_nullifier(voter_key, @election.id)
          @already_voted = ::Election::EligibilityProofService.already_voted?(nullifier, @election.id)
        else
          @already_voted = false
        end

        # Ballot routing preview (what sections they'll vote on)
        @ballot_route = ::Election::BallotRoutingService.route(current_citizen, @election.id)
        @is_diaspora = @ballot_route[:type] == :diaspora
      end

      # ── Step 2: Begin Voting (after liveness) ──────────────────
      # Generates challenge nonce and stores ballot route in session.
      def begin
        election = active_election

        # Liveness session validation
        liveness_session_id = params[:liveness_session_id]
        biometric_hash = params[:biometric_hash]

        unless liveness_session_id.present?
          redirect_to citizens_election_vote_path, alert: t("citizens.election.liveness_required")
          return
        end

        # Derive voter key
        voter_key = ::Election::EligibilityProofService.derive_voter_key(
          current_citizen.bonid,
          liveness_session_id,
          biometric_hash || current_citizen.id_number.to_s
        )

        # Generate nullifier
        nullifier = ::Election::EligibilityProofService.generate_nullifier(voter_key, election.id)

        # Double-vote check
        if ::Election::EligibilityProofService.already_voted?(nullifier, election.id)
          redirect_to citizens_election_vote_path, alert: t("citizens.election.already_voted")
          return
        end

        # Issue challenge nonce (10 min expiry)
        challenge_nonce = SecureRandom.hex(32)
        Rails.cache.write(
          "election_challenge:#{current_citizen.id}:#{election.id}",
          challenge_nonce,
          expires_in: 10.minutes
        )

        # Route ballot
        ballot_route = ::Election::BallotRoutingService.route(current_citizen, election.id)

        # Store in session (not the full candidate list — re-fetch in ballot action)
        session[:election_vote] = {
          election_id: election.id,
          voter_key: voter_key,
          nullifier: nullifier,
          challenge_nonce: challenge_nonce,
          liveness_session_id: liveness_session_id,
          biometric_hash: biometric_hash || current_citizen.id_number.to_s,
          ballot_type: ballot_route[:type].to_s,
          department: ballot_route[:department],
          started_at: Time.current.iso8601
        }

        redirect_to citizens_election_vote_ballot_path
      end

      # ── Step 3: Show Ballot ────────────────────────────────────
      # Displays candidates grouped by section (immersive mode).
      def ballot
        vote_session = session[:election_vote]
        unless vote_session
          redirect_to citizens_election_vote_path, alert: t("citizens.election.session_expired")
          return
        end

        # Check nonce hasn't expired
        cached_nonce = Rails.cache.read("election_challenge:#{current_citizen.id}:#{vote_session['election_id']}")
        unless cached_nonce == vote_session["challenge_nonce"]
          session.delete(:election_vote)
          redirect_to citizens_election_vote_path, alert: t("citizens.election.session_expired")
          return
        end

        @election = BonvoteElection.find(vote_session["election_id"])
        @ballot_route = ::Election::BallotRoutingService.route(current_citizen, @election.id)
        @sections = @ballot_route[:ballot_sections]
        @challenge_nonce = vote_session["challenge_nonce"]
        @voter_key = vote_session["voter_key"]
        @nullifier = vote_session["nullifier"]

        # CEP public key for client-side encryption
        @cep_public_key = ::Election::ElectionCache.cep_public_key(@election.id)
      end

      # ── Step 4: Cast Vote ──────────────────────────────────────
      # Receives encrypted ballot from client, stores it.
      def cast
        vote_session = session[:election_vote]
        unless vote_session
          redirect_to citizens_election_vote_path, alert: t("citizens.election.session_expired")
          return
        end

        election_id = vote_session["election_id"]
        election = BonvoteElection.find(election_id)

        # Idempotency — check if already cast with this nullifier
        existing = ElectionBallot.find_by(nullifier: vote_session["nullifier"], election_id: election_id)
        if existing
          session[:election_receipt] = {
            ballot_hash: existing.ballot_hash,
            receipt_id: existing.receipt_id,
            election_id: election_id,
            timestamp: existing.cast_at&.iso8601
          }
          session.delete(:election_vote)
          redirect_to citizens_election_vote_receipt_path
          return
        end

        # Cast via service
        result = ::Election::BallotService.cast(
          citizen: current_citizen,
          election_id: election_id,
          choice: 0, # Server never knows — choice is in encrypted_choice
          liveness_session_id: vote_session["liveness_session_id"],
          biometric_hash: vote_session["biometric_hash"],
          cep_public_key: ::Election::ElectionCache.cep_public_key(election_id)
        )

        # Store ballot
        location_code = current_citizen.bonid.to_s.split("-")[3]&.upcase
        ip_country = IpGeolocator.country_code(request.remote_ip) rescue nil

        ElectionBallot.create!(
          election_id: election_id,
          nullifier: result[:ballot][:nullifier],
          position: params[:position] || "president",
          encrypted_choice: (params[:encrypted_choice] || result[:ballot][:encrypted_choice]).to_json,
          encrypted_key: params.dig(:encrypted_choice, :encrypted_key) || result[:ballot].dig(:encrypted_choice, :encrypted_key),
          iv: params.dig(:encrypted_choice, :iv) || result[:ballot].dig(:encrypted_choice, :iv),
          auth_tag: params.dig(:encrypted_choice, :auth_tag) || result[:ballot].dig(:encrypted_choice, :auth_tag),
          zkp_commitment: result[:ballot][:zkp_commitment],
          zkp_proof: result[:ballot][:zkp_proof],
          ballot_hash: result[:receipt][:ballot_hash],
          receipt_id: result[:receipt][:receipt_id],
          channel: "remote",
          department_code: location_code,
          ip_country: ip_country,
          location_flagged: ip_country.present? && location_code.present? && ip_country.upcase != location_code,
          cast_at: Time.current
        )

        # Broadcast to CEP dashboard
        ::Election::ElectionCache.increment_vote_count!(election_id)

        # Store receipt in session
        session[:election_receipt] = {
          ballot_hash: result[:receipt][:ballot_hash],
          receipt_id: result[:receipt][:receipt_id],
          election_id: election_id,
          timestamp: result[:receipt][:timestamp]
        }

        session.delete(:election_vote)
        redirect_to citizens_election_vote_receipt_path

      rescue ::Election::BallotService::AlreadyVotedError
        session.delete(:election_vote)
        redirect_to citizens_election_vote_path, alert: t("citizens.election.already_voted")
      rescue => e
        Rails.logger.error("[Citizens::Election::Vote] Cast failed: #{e.message}")
        redirect_to citizens_election_vote_ballot_path, alert: t("citizens.election.cast_error")
      end

      # ── Step 5: Receipt ────────────────────────────────────────
      def receipt
        @receipt = session[:election_receipt]
        unless @receipt
          redirect_to citizens_election_vote_path
          return
        end

        @election = BonvoteElection.find_by(id: @receipt["election_id"])
        @verify_url = "#{request.base_url}/election/verify?hash=#{@receipt['ballot_hash']}"
      end

      private

      def enable_immersive_form
        @immersive_form = true
      end
    end
  end
end
