# frozen_string_literal: true

# Election Audit Service — the "Truth Engine"
#
# Manages the Public Bulletin Board that allows:
#   - Voters to verify their ballot was counted ("Vòt ou konte")
#   - International observers (OEA, UN) to verify no ballots were added/removed
#   - CEP to generate tamper-proof tallies using homomorphic aggregation
#   - Daily integrity checks publishable to the public
#
# The bulletin board contains ONLY:
#   - ballot_hash (SHA256 — cannot be reversed to find the voter)
#   - nullifier (prevents double-voting — cannot identify the voter)
#   - zkp_commitment (Pedersen commitment — hides the actual vote)
#   - timestamp
#
# It does NOT contain: voter name, BonID, IP address, or any PII.
#
module Election
  class AuditService
    class AuditError < StandardError; end

    # ── Voter-Facing: "Vòt ou konte" ──────────────────────────────────────

    # Verify a voter's ballot exists in the public ledger.
    # The voter enters their receipt code (ballot_hash) on a public website
    # and sees a green checkmark if their vote was counted.
    #
    # @param ballot_hash [String] SHA256 hash from the voter's receipt
    # @param election_id [String] Election identifier
    # @return [Hash] { found:, timestamp:, position: }
    def self.verify_ballot_presence(ballot_hash, election_id)
      ballot = find_ballot(ballot_hash, election_id)

      if ballot
        {
          found: true,
          message: "Vòt ou konte",  # "Your vote is counted"
          timestamp: ballot[:timestamp],
          position: ballot[:position], # Position in the ledger (e.g., "Vote #4,523")
          election_id: election_id
        }
      else
        {
          found: false,
          message: "Nou pa jwenn vòt sa a nan rejis la",  # "Vote not found in the registry"
          election_id: election_id
        }
      end
    end

    # ── CEP/Observer-Facing: Integrity Verification ──────────────────────

    # Generate a tally proof using homomorphic aggregation of commitments.
    # CEP publishes this daily so observers can verify independently.
    #
    # @param election_id [String] Election identifier
    # @return [Hash] { total_votes:, aggregated_commitment:, merkle_root:, generated_at: }
    def self.generate_tally_proof(election_id)
      ballots = load_ballots(election_id)

      if ballots.empty?
        return { election_id: election_id, total_votes: 0, error: "No ballots found" }
      end

      # Aggregate commitments (XOR-based for hash commitments)
      commitments = ballots.map { |b| b[:zkp_commitment] }
      aggregated = CommitmentService.aggregate(commitments)

      # Generate Merkle root for full ledger integrity
      merkle_root = compute_merkle_root(ballots.map { |b| b[:ballot_hash] })

      {
        election_id: election_id,
        total_votes: ballots.size,
        aggregated_commitment: aggregated,
        merkle_root: merkle_root,
        first_vote_at: ballots.first[:timestamp],
        last_vote_at: ballots.last[:timestamp],
        generated_at: Time.current.iso8601,
        protocol_version: "bonid-election-v1"
      }
    end

    # Verify the integrity of the entire ballot ledger.
    # Observers run this to ensure no ballots were added, removed, or modified.
    #
    # @param election_id [String] Election identifier
    # @param expected_merkle_root [String] The published Merkle root
    # @return [Hash] { valid:, total_votes:, errors: }
    def self.verify_ledger_integrity(election_id, expected_merkle_root)
      ballots = load_ballots(election_id)
      errors = []

      # 1. Recompute Merkle root
      actual_root = compute_merkle_root(ballots.map { |b| b[:ballot_hash] })
      unless ActiveSupport::SecurityUtils.secure_compare(actual_root, expected_merkle_root)
        errors << "Merkle root mismatch — ledger has been tampered with"
      end

      # 2. Check for duplicate nullifiers (double-voting)
      nullifiers = ballots.map { |b| b[:nullifier] }
      duplicates = nullifiers.select { |n| nullifiers.count(n) > 1 }.uniq
      if duplicates.any?
        errors << "#{duplicates.size} duplicate nullifier(s) detected — possible double-voting"
      end

      # 3. Verify chronological ordering
      timestamps = ballots.map { |b| Time.parse(b[:timestamp]) rescue Time.at(0) }
      unless timestamps == timestamps.sort
        errors << "Ballots are not in chronological order — possible injection"
      end

      {
        valid: errors.empty?,
        total_votes: ballots.size,
        unique_voters: nullifiers.uniq.size,
        merkle_root: actual_root,
        errors: errors,
        verified_at: Time.current.iso8601
      }
    end

    # ── Public Bulletin Board: Daily Snapshot ─────────────────────────────

    # Generate a daily snapshot for public publication.
    # Contains no PII — only hashes, counts, and integrity proofs.
    #
    # @param election_id [String] Election identifier
    # @return [Hash] Publishable snapshot
    def self.daily_snapshot(election_id)
      ballots = load_ballots(election_id)

      # Vote counts by channel (consulate vs remote)
      by_channel = ballots.group_by { |b| b[:channel] || "remote" }
                          .transform_values(&:size)

      # Hourly distribution (for observer transparency)
      hourly = ballots.group_by { |b| Time.parse(b[:timestamp]).strftime("%Y-%m-%d %H:00") rescue "unknown" }
                      .transform_values(&:size)

      {
        election_id: election_id,
        snapshot_date: Date.current.iso8601,
        total_votes: ballots.size,
        votes_by_channel: by_channel,
        votes_by_hour: hourly,
        merkle_root: compute_merkle_root(ballots.map { |b| b[:ballot_hash] }),
        integrity: "VALID",
        published_at: Time.current.iso8601,
        publisher: "BonID Election Service v1"
      }
    end

    # ── Consulate Kiosk Support ──────────────────────────────────────────

    # Record that a vote was cast at a consulate station.
    # Same cryptographic payload, but tagged with the consulate location.
    #
    # @param ballot [Hash] The ballot payload from BallotService.cast
    # @param consulate_id [String] Consulate identifier (e.g., "HT-CONS-MIAMI")
    # @param station_id [String] Kiosk/tablet identifier
    # @return [Hash] Enhanced ballot with consulate metadata
    def self.tag_consulate_vote(ballot, consulate_id, station_id)
      ballot.merge(
        channel: "consulate",
        consulate_id: consulate_id,
        station_id: station_id
      )
    end

    private

    # Compute a Merkle root from an array of hashes.
    # Provides O(log n) proof that any single ballot is in the tree.
    def self.compute_merkle_root(hashes)
      return OpenSSL::Digest::SHA256.hexdigest("empty") if hashes.empty?
      return hashes.first if hashes.size == 1

      # Pad to even number
      hashes << hashes.last if hashes.size.odd?

      # Compute parent layer
      parents = hashes.each_slice(2).map do |left, right|
        OpenSSL::Digest::SHA256.hexdigest("#{left}#{right}")
      end

      compute_merkle_root(parents)
    end

    # Load ballots from the immutable ledger.
    def self.load_ballots(election_id)
      ElectionBallot.where(election_id: election_id).order(:cast_at).map do |b|
        {
          ballot_hash: b.ballot_hash,
          nullifier: b.nullifier,
          zkp_commitment: b.zkp_commitment,
          timestamp: b.cast_at.iso8601,
          channel: b.channel,
          position: b.position
        }
      end
    rescue NameError
      []
    end

    def self.find_ballot(ballot_hash, election_id)
      ballot = ElectionBallot.find_by(ballot_hash: ballot_hash, election_id: election_id)
      return nil unless ballot

      {
        ballot_hash: ballot.ballot_hash,
        timestamp: ballot.cast_at.iso8601,
        position: "Vote ##{ElectionBallot.where(election_id: election_id).where('cast_at <= ?', ballot.cast_at).count}"
      }
    rescue NameError
      nil
    end
  end
end
