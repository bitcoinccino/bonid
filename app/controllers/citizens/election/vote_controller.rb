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
      # Vote-casting is paused for BonVote v1 (2026-04-20 scope: register
      # voters only, no ballot casting). Every action redirects to the
      # enrollment page until FEATURE_BONVOTE_TALLY is flipped on.
      before_action :enforce_bonvote_tally_flag!
      before_action :require_verified_bonid!
      before_action :require_active_election!, only: [ :begin, :ballot, :cast ]
      before_action :require_online_voting_enabled!, only: [ :begin, :ballot, :cast ]
      before_action :enable_immersive_form, only: [ :ballot, :cast, :receipt ]

      # ── Step 0: Oath of Voting Integrity ───────────────────────
      # A sworn, per-session acknowledgment shown before anything else.
      # Explains what the citizen is about to do, the security measures
      # that protect their vote, and the civil + criminal consequences
      # of attempting to defraud the election. Must be signed (checkbox)
      # once per session — the flag clears on logout.
      def oath
        @election = active_election
        @already_signed = oath_signed?
        @bonid_submission = current_citizen.identity_submissions.find_by(status: "approved")
      end

      # Records the oath both as a durable DB row (for CEP / tribunal
      # audit) and in the session (so the gate doesn't re-prompt within
      # the same browsing session). The DB row is the source of truth —
      # session is just a soft cache.
      def sign_oath
        unless params[:oath_accepted] == "1"
          redirect_to citizens_election_vote_oath_path,
                      alert: "Ou dwe aksepte sèman an pou w kapab vote."
          return
        end

        election = active_election
        record = if election
          VoterOathAcknowledgement.sign!(
            user: current_citizen,
            bonvote_election: election,
            identity_submission: current_citizen.identity_submissions.find_by(status: "approved"),
            ip_address: request.remote_ip,
            user_agent: request.user_agent
          )
        end

        session[:election_oath_signed_at] = (record&.accepted_at || Time.current).iso8601
        Rails.logger.info(
          "[Citizens::Election::Vote] Oath signed by user ##{current_citizen.id} " \
          "election=#{election&.id || 'none'} record_id=#{record&.id || 'n/a'} " \
          "digest=#{record&.digest&.first(12) || 'n/a'}"
        )
        redirect_to citizens_election_vote_path
      end

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

        # Sworn oath is a prerequisite. Skip the gate once the voter has
        # already cast (they'll see the receipt path) so the oath doesn't
        # re-prompt on a refresh of the post-vote state.
        unless oath_signed?
          redirect_to citizens_election_vote_oath_path
          return
        end

        # Check voter roll
        @voter_record = VoterEligibilityRecord.check_eligibility(election: @election, bonid: current_citizen.bonid)
        @has_cin = @voter_record&.eligible? || current_citizen.id_number.present?

        # Gate #1 — Enrollment face must exist on the roll. The fallback
        # biometric_anchor (BonID hash) can't match against a real Rekognition
        # face, so a liveness scan for a voter without a biometric_fingerprint
        # would fail the downstream CompareFaces step anyway. Refuse to render
        # the scan button at all.
        @has_enrolled_face = @voter_record&.biometric_fingerprint.present?

        # Gate #2 — Per-user 5-min scan cooldown. Set on every successful
        # `begin` hit so a citizen can't re-fire the billed AWS session by
        # refreshing / back-buttoning.
        @scan_cooldown_remaining = scan_cooldown_remaining_seconds

        # Resumable verification — a previously-passed liveness session that
        # hasn't been cast yet. Lives 15 min in Rails.cache; lets a citizen
        # close the tab / log out / come back without paying for AWS again.
        @resume_payload = Rails.cache.read(resume_cache_key(@election.id))
        @resume_remaining = resume_cache_remaining_seconds(@election.id) if @resume_payload

        # Generate nullifier to check double-voting (using biometric anchor from voter roll)
        if @voter_record&.eligible?
          voter_key = ::Election::EligibilityProofService.derive_voter_key(
            current_citizen.bonid,
            "eligibility-check",
            @voter_record.biometric_anchor
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

        # Gate #1 — Refuse if the voter has no enrolled biometric face on the roll.
        # (Fallback BonID-hash anchor can't satisfy downstream CompareFaces.)
        voter_record = VoterEligibilityRecord.check_eligibility(election: election, bonid: current_citizen.bonid)
        unless voter_record&.biometric_fingerprint.present?
          redirect_to citizens_election_vote_path,
                      alert: "Ou pa gen anrejistreman biyometrik. Ale nan yon biwo CEP pou w enskri figi ou anvan w vote."
          return
        end

        # Gate #1b — Identity binding. Liveness only proves a real live face
        # was in front of the camera. This call proves the face was THIS
        # citizen's face, by comparing the liveness selfie to the selfie
        # approved at KYC. Fails closed on any AWS / storage error.
        match = ::Election::VoterFaceMatchService.call(
          user: current_citizen,
          liveness_blob_signed_id: liveness_session_id
        )
        unless match.matched?
          Rails.logger.warn(
            "[Citizens::Election::Vote] Face match refused for user ##{current_citizen.id}: " \
            "status=#{match.status} similarity=#{match.similarity}"
          )
          mark_scan_cooldown!
          redirect_to citizens_election_vote_path,
                      alert: "Figi eskané a pa matche ak figi ki nan dosye idantite ou. Pou sekirite vòt ou, nou pa ka kontinye."
          return
        end

        # Gate #2 — 5-minute per-user scan cooldown. `begin` is the first
        # server hit after a billed AWS liveness session fires, so stamping
        # the cooldown here stops repeat scans from double-submits, refreshes,
        # and back-button flows within the same 5-minute window.
        mark_scan_cooldown!

        # Resolve biometric anchor from voter roll (Rekognition face_id hash)
        biometric_anchor = voter_record&.biometric_anchor || OpenSSL::Digest::SHA256.hexdigest(current_citizen.bonid.to_s)

        # Derive voter key: BonID + liveness session + biometric anchor
        # The biometric_hash from liveness is combined with the enrolled face_id hash
        # so even a stolen session can't produce the correct nullifier
        combined_biometric = OpenSSL::Digest::SHA256.hexdigest(
          "#{biometric_hash || "none"}||#{biometric_anchor}"
        )

        voter_key = ::Election::EligibilityProofService.derive_voter_key(
          current_citizen.bonid,
          liveness_session_id,
          combined_biometric
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
        vote_payload = {
          election_id: election.id,
          voter_key: voter_key,
          nullifier: nullifier,
          challenge_nonce: challenge_nonce,
          liveness_session_id: liveness_session_id,
          biometric_hash: combined_biometric,
          ballot_type: ballot_route[:type].to_s,
          department: ballot_route[:department],
          started_at: Time.current.iso8601
        }
        session[:election_vote] = vote_payload

        # Mirror the payload into Rails.cache so the citizen can resume
        # after a logout / tab close without rescanning (15-min window).
        Rails.cache.write(
          resume_cache_key(election.id),
          vote_payload.merge(cached_at: Time.current.to_i),
          expires_in: RESUME_WINDOW
        )

        redirect_to citizens_election_vote_ballot_path
      end

      # ── Resume Voting (post-liveness, pre-cast) ────────────────
      # Restores a cached verification payload into the session so the
      # citizen can pick up where they left off without a new AWS scan.
      def resume
        election = active_election
        unless election
          redirect_to citizens_election_vote_path, alert: t("citizens.election.session_expired")
          return
        end

        payload = Rails.cache.read(resume_cache_key(election.id))
        unless payload && payload[:election_id] == election.id
          redirect_to citizens_election_vote_path, alert: t("citizens.election.session_expired")
          return
        end

        # Double-vote check — payload could be stale if the ballot was cast
        # from another device since the cache was written.
        if ::Election::EligibilityProofService.already_voted?(payload[:nullifier], election.id)
          Rails.cache.delete(resume_cache_key(election.id))
          redirect_to citizens_election_vote_path, alert: t("citizens.election.already_voted")
          return
        end

        # Re-arm the challenge nonce so the ballot action's expiry check passes.
        Rails.cache.write(
          "election_challenge:#{current_citizen.id}:#{election.id}",
          payload[:challenge_nonce],
          expires_in: 10.minutes
        )

        session[:election_vote] = payload.except(:cached_at)
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
          # Track collision for CEP monitoring (silent — voter sees normal receipt)
          ::Election::NullifierCollisionTracker.record!(
            election_id,
            nullifier: vote_session["nullifier"],
            ip_address: request.remote_ip,
            channel: "remote",
            department_code: current_citizen.bonid.to_s.split("-")[3]&.upcase
          )

          session[:election_receipt] = {
            ballot_hash: existing.ballot_hash,
            receipt_id: existing.receipt_id,
            election_id: election_id,
            timestamp: existing.cast_at&.iso8601
          }
          session.delete(:election_vote)
          Rails.cache.delete(resume_cache_key(election_id))
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

        # Track velocity for spike detection
        ::Election::VelocityMonitorService.record_vote!(election_id, department_code: location_code)

        # Store receipt in session
        session[:election_receipt] = {
          ballot_hash: result[:receipt][:ballot_hash],
          receipt_id: result[:receipt][:receipt_id],
          election_id: election_id,
          timestamp: result[:receipt][:timestamp]
        }

        session.delete(:election_vote)
        Rails.cache.delete(resume_cache_key(election_id))
        redirect_to citizens_election_vote_receipt_path

      rescue ::Election::BallotService::AlreadyVotedError
        session.delete(:election_vote)
        Rails.cache.delete(resume_cache_key(election_id))
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

        # Surface the oath signature on the receipt — turns the invisible
        # legal artifact into visible UX trust without prompting any new
        # signing moment.
        @oath = if @election
                  VoterOathAcknowledgement.find_by(
                    user: current_citizen,
                    bonvote_election: @election,
                    oath_version: VoterOathAcknowledgement::CURRENT_VERSION
                  )
        end
      end

      private

      # Paused for v1 — no citizen vote-casting. Only register-to-vote ships.
      # When `FEATURE_BONVOTE_TALLY=true` is flipped, this becomes a no-op
      # and the wizard becomes live again without any other change.
      def enforce_bonvote_tally_flag!
        return if ENV["FEATURE_BONVOTE_TALLY"].to_s.downcase == "true"

        redirect_to citizens_election_enrollment_path,
                    alert: "Vòt an liy poze pou kounye a. BonVote ap ede w anrejistre sèlman nan faz sa a."
      end

      def enable_immersive_form
        @immersive_form = true
      end

      # ── Online-voting gate ─────────────────────────────────────
      # Refuses the begin/ballot/cast surface when either
      #   (a) the election itself has `allows_online_voting = false`
      #       (paper-only election — CEP policy decision), or
      #   (b) the citizen's VoterEligibilityRecord explicitly opted
      #       `preferred_channel = "in_person"` at enrollment.
      # In both cases we send them back to Eleksyon Mwen so they can
      # either update their preference or go to their assigned BV.
      def require_online_voting_enabled!
        election = active_election
        return unless election

        unless election.allows_online_voting?
          redirect_to citizens_election_enrollment_path,
                      alert: "Eleksyon sa a se vote an pèsòn sèlman. Ale nan biwo vòt ou a."
          return
        end

        voter_record = VoterEligibilityRecord.check_eligibility(
          election: election, bonid: current_citizen.bonid
        )
        return unless voter_record&.preferred_channel == "in_person"

        redirect_to citizens_election_enrollment_path,
                    alert: "Ou te chwazi vote an pèsòn. Ale nan biwo vòt ou a oswa chanje preferans ou."
      end

      # ── Oath ───────────────────────────────────────────────────
      # The DB is the source of truth for audit integrity. The session
      # is only a soft cache; if the session says "signed" but no DB
      # row exists (e.g. legacy session from before the audit table
      # existed) we backfill so every signed state leaves an evidence
      # trail the CEP can see.
      def oath_signed?
        election = active_election
        return session[:election_oath_signed_at].present? unless election

        signed = VoterOathAcknowledgement.signed?(
          user: current_citizen, bonvote_election: election
        )

        if !signed && session[:election_oath_signed_at].present?
          record = VoterOathAcknowledgement.sign!(
            user: current_citizen,
            bonvote_election: election,
            identity_submission: current_citizen.identity_submissions.find_by(status: "approved"),
            ip_address: request.remote_ip,
            user_agent: request.user_agent
          )
          Rails.logger.info(
            "[Citizens::Election::Vote] Oath backfilled for user ##{current_citizen.id} " \
            "election=#{election.id} record_id=#{record&.id} digest=#{record&.digest&.first(12)}"
          )
          signed = record.present?
        end

        # Keep the session warm so subsequent requests skip the lookup.
        session[:election_oath_signed_at] ||= Time.current.iso8601 if signed
        signed
      end

      # ── Resume window ──────────────────────────────────────────
      # How long a passed-but-not-cast verification survives so a citizen
      # can resume without rescanning. Longer than the 10-min challenge
      # nonce because `resume` re-arms the nonce on pick-up.
      RESUME_WINDOW = 15.minutes

      def resume_cache_key(election_id)
        "election:verified:#{current_citizen.id}:#{election_id}"
      end

      def resume_cache_remaining_seconds(election_id)
        payload = Rails.cache.read(resume_cache_key(election_id))
        return 0 unless payload && payload[:cached_at]

        remaining = RESUME_WINDOW.to_i - (Time.current.to_i - payload[:cached_at].to_i)
        [ remaining, 0 ].max
      end

      # ── Scan cooldown ──────────────────────────────────────────
      # 5-minute per-citizen cooldown between billed AWS FaceLiveness
      # sessions. Cheap Rails.cache counter, keyed by citizen id.
      SCAN_COOLDOWN = 5.minutes

      def scan_cooldown_key
        "election:scan_cooldown:#{current_citizen.id}"
      end

      # Seconds left on the cooldown, or 0 if not active.
      def scan_cooldown_remaining_seconds
        started_at = Rails.cache.read(scan_cooldown_key)
        return 0 unless started_at

        remaining = SCAN_COOLDOWN.to_i - (Time.current.to_i - started_at.to_i)
        [ remaining, 0 ].max
      end

      def mark_scan_cooldown!
        Rails.cache.write(scan_cooldown_key, Time.current.to_i, expires_in: SCAN_COOLDOWN)
      end
    end
  end
end
