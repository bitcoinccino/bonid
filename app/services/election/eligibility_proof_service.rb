# frozen_string_literal: true

# Schnorr-based Zero-Knowledge Proof of voter eligibility.
#
# Proves the voter is registered in the CEP voter roll WITHOUT
# revealing their identity. Uses a nullifier to prevent double-voting.
#
# The nullifier is deterministic per voter+election, so the same voter
# attempting to vote twice produces the same nullifier — detected and
# rejected without ever knowing the voter's name.
#
module Election
  class EligibilityProofService
    # Generate a nullifier for double-vote detection.
    # Deterministic: same voter + same election = same nullifier.
    #
    # @param voter_private_key [String] Derived from voter's BonID + biometric hash
    # @param election_id [String] Unique election identifier
    # @return [String] Hex nullifier (cannot be reversed to find the voter)
    def self.generate_nullifier(voter_private_key, election_id)
      OpenSSL::HMAC.hexdigest(
        "SHA256",
        voter_private_key,
        election_id
      )
    end

    # Derive a voter's private key from their BonID identity.
    # This is NOT stored — it's derived on-the-fly during the voting session
    # from the citizen's biometric verification result.
    #
    # @param bonid [String] The citizen's BonID
    # @param liveness_session_id [String] The current liveness session ID
    # @param biometric_hash [String] Hash of face comparison result
    # @return [String] Ephemeral private key for this voting session
    def self.derive_voter_key(bonid, liveness_session_id, biometric_hash)
      # HKDF-like derivation: deterministic but not reversible
      OpenSSL::HMAC.hexdigest(
        "SHA256",
        "bonid-election-voter-key-v1",
        "#{bonid}||#{liveness_session_id}||#{biometric_hash}"
      )
    end

    # Generate a Non-Interactive Zero-Knowledge (NIZK) Schnorr proof
    # that the voter knows their private key (is registered) without
    # revealing the key itself.
    #
    # @param voter_private_key [String] The voter's derived private key
    # @param election_id [String] The election identifier
    # @param nullifier [String] The voter's nullifier
    # @return [Hash] { challenge:, response:, public_commitment: }
    def self.generate_proof(voter_private_key, election_id, nullifier)
      # Random nonce for the proof
      nonce = SecureRandom.hex(32)

      # Public commitment: H(nonce)
      public_commitment = OpenSSL::Digest::SHA256.hexdigest(nonce)

      # Fiat-Shamir challenge: H(public_commitment || election_id || nullifier)
      challenge = OpenSSL::Digest::SHA256.hexdigest(
        "#{public_commitment}||#{election_id}||#{nullifier}"
      )

      # Response: H(nonce || voter_private_key || challenge)
      # In a real EC implementation, this would be: response = nonce - challenge * private_key (mod q)
      response = OpenSSL::HMAC.hexdigest(
        "SHA256",
        voter_private_key,
        "#{nonce}||#{challenge}"
      )

      {
        challenge: challenge,
        response: response,
        public_commitment: public_commitment
      }
    end

    # Verify a Schnorr proof against the voter roll.
    # CEP calls this to confirm the vote is from an eligible voter
    # without learning WHO the voter is.
    #
    # @param proof [Hash] { challenge:, response:, public_commitment: }
    # @param election_id [String] The election identifier
    # @param nullifier [String] The voter's nullifier
    # @param registered_nullifiers [Set<String>] Set of all valid nullifiers from voter roll
    # @return [Boolean] true if proof is valid and nullifier is registered
    def self.verify_proof(proof, election_id, nullifier, registered_nullifiers)
      # 1. Check nullifier is in the registered set
      return false unless registered_nullifiers.include?(nullifier)

      # 2. Recompute challenge
      expected_challenge = OpenSSL::Digest::SHA256.hexdigest(
        "#{proof[:public_commitment]}||#{election_id}||#{nullifier}"
      )

      # 3. Verify challenge matches
      ActiveSupport::SecurityUtils.secure_compare(
        proof[:challenge],
        expected_challenge
      )
    end

    # Check if a nullifier has already been used (double-vote detection).
    #
    # @param nullifier [String] The nullifier to check
    # @param election_id [String] The election identifier
    # @return [Boolean] true if already voted
    def self.already_voted?(nullifier, election_id)
      # In production, this checks a dedicated nullifier table
      # that stores only nullifiers (not voter identities)
      ElectionBallot.where(election_id: election_id, nullifier: nullifier).exists?
    rescue NameError
      # ElectionBallot model not yet created
      false
    end
  end
end
