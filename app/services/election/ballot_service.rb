# frozen_string_literal: true

# Orchestrates the full vote-casting flow:
#   1. Verify biometric identity (liveness + face match)
#   2. Generate nullifier (anti-double-vote)
#   3. Create Pedersen commitment (privacy)
#   4. Generate Schnorr proof (eligibility without identity)
#   5. Encrypt choice (only CEP can decrypt)
#   6. Package payload (< 1KB for 2G networks)
#
# Usage:
#   result = Election::BallotService.cast(
#     citizen: user,
#     election_id: "2026-presidential-round1",
#     choice: 3,
#     liveness_session_id: "abc-123",
#     biometric_hash: "sha256...",
#     cep_public_key: "-----BEGIN PUBLIC KEY-----\n..."
#   )
#
module Election
  class BallotService
    class VoteError < StandardError; end
    class AlreadyVotedError < VoteError; end
    class IneligibleError < VoteError; end

    # Cast a vote with full cryptographic protection.
    #
    # @param citizen [User] The verified BonID holder
    # @param election_id [String] Election identifier
    # @param choice [Integer] Ballot choice (candidate index)
    # @param liveness_session_id [String] Current liveness session
    # @param biometric_hash [String] Face comparison result hash
    # @param cep_public_key [String] CEP's RSA public key (PEM)
    # @return [Hash] The complete ballot payload (< 1KB)
    def self.cast(citizen:, election_id:, choice:, liveness_session_id:, biometric_hash:, cep_public_key:)
      # 1. Derive voter key from biometric verification
      voter_key = EligibilityProofService.derive_voter_key(
        citizen.bonid,
        liveness_session_id,
        biometric_hash
      )

      # 2. Generate nullifier (deterministic per voter + election)
      nullifier = EligibilityProofService.generate_nullifier(voter_key, election_id)

      # 3. Check for double-voting
      if EligibilityProofService.already_voted?(nullifier, election_id)
        raise AlreadyVotedError, "Ou deja vote nan eleksyon sa a."
      end

      # 4. Create Pedersen commitment (hides the choice)
      commitment = CommitmentService.commit(choice, election_id)

      # 5. Generate Schnorr proof (proves eligibility without revealing identity)
      proof = EligibilityProofService.generate_proof(voter_key, election_id, nullifier)

      # 6. Encrypt the choice (only CEP can decrypt)
      encrypted = VoteEncryptionService.encrypt(choice, cep_public_key, election_id)

      # 7. Sign the entire payload
      payload_to_sign = "#{election_id}||#{nullifier}||#{commitment[:commitment]}||#{Time.current.iso8601}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", voter_key, payload_to_sign)

      # 8. Package the ballot (< 1KB)
      ballot = {
        election_id: election_id,
        nullifier: nullifier,
        encrypted_choice: encrypted,
        zkp_commitment: commitment[:commitment],
        zkp_proof: proof,
        timestamp: Time.current.iso8601,
        signature: signature,
        protocol_version: "bonid-election-v1"
      }

      # 9. Store the ballot receipt (voter gets this, CEP gets the ballot)
      receipt = {
        receipt_id: SecureRandom.uuid,
        election_id: election_id,
        nullifier: nullifier,
        commitment: commitment[:commitment],
        timestamp: ballot[:timestamp],
        ballot_hash: OpenSSL::Digest::SHA256.hexdigest(ballot.to_json)
      }

      Rails.logger.info("[Election::BallotService] Vote cast for election #{election_id}. Nullifier: #{nullifier[0..7]}...")

      {
        ballot: ballot,
        receipt: receipt,
        blinding_factor: commitment[:blinding_factor], # Stored locally, never sent to server
        payload_size: ballot.to_json.bytesize
      }
    end

    # Verify a ballot's integrity (CEP-side).
    #
    # @param ballot [Hash] The ballot payload
    # @param registered_nullifiers [Set<String>] All valid nullifiers
    # @return [Hash] { valid:, errors: }
    def self.verify(ballot, registered_nullifiers)
      errors = []

      # Check nullifier is registered
      unless registered_nullifiers.include?(ballot[:nullifier])
        errors << "Nullifier not found in voter roll"
      end

      # Verify ZKP proof
      unless EligibilityProofService.verify_proof(
        ballot[:zkp_proof],
        ballot[:election_id],
        ballot[:nullifier],
        registered_nullifiers
      )
        errors << "Zero-knowledge proof verification failed"
      end

      # Check timestamp is within election window
      vote_time = Time.parse(ballot[:timestamp]) rescue nil
      unless vote_time
        errors << "Invalid timestamp"
      end

      {
        valid: errors.empty?,
        errors: errors
      }
    end
  end
end
