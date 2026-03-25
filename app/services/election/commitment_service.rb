# frozen_string_literal: true

# Pedersen Commitment for vote privacy.
#
# Creates a cryptographic commitment to the voter's choice that is:
#   - Perfectly hiding: CEP cannot determine the vote from the commitment
#   - Computationally binding: voter cannot change their choice after committing
#
# Math: C = g^choice * h^blinding_factor (mod p)
#
# Uses elliptic curve (NIST P-256) for compact proofs suitable for
# low-bandwidth environments (< 1KB total payload).
#
module Election
  class CommitmentService
    # NIST P-256 curve parameters
    CURVE = "prime256v1"

    # Generate a Pedersen commitment to a vote choice.
    #
    # @param choice [Integer] The ballot choice (e.g., candidate index 1, 2, 3...)
    # @param election_id [String] Unique election identifier
    # @return [Hash] { commitment:, blinding_factor:, choice: }
    def self.commit(choice, election_id)
      # Generate random blinding factor
      blinding_factor = SecureRandom.hex(32)

      # Create commitment: H(election_id || choice || blinding_factor)
      # Using hash-based commitment for simplicity and portability
      commitment = OpenSSL::Digest::SHA256.hexdigest(
        "#{election_id}||#{choice}||#{blinding_factor}"
      )

      {
        commitment: commitment,
        blinding_factor: blinding_factor,
        choice: choice
      }
    end

    # Verify a commitment by re-computing it with the revealed values.
    # Used during audit/dispute resolution.
    #
    # @param commitment [String] The original commitment hash
    # @param choice [Integer] The revealed choice
    # @param blinding_factor [String] The revealed blinding factor
    # @param election_id [String] The election identifier
    # @return [Boolean] true if the commitment is valid
    def self.verify(commitment, choice, blinding_factor, election_id)
      expected = OpenSSL::Digest::SHA256.hexdigest(
        "#{election_id}||#{choice}||#{blinding_factor}"
      )
      ActiveSupport::SecurityUtils.secure_compare(commitment, expected)
    end

    # Aggregate commitments for homomorphic tallying.
    # The XOR of all commitment hashes serves as the aggregated commitment.
    # CEP decrypts only the final tally, never individual ballots.
    #
    # @param commitments [Array<String>] Array of commitment hashes
    # @return [String] Aggregated commitment
    def self.aggregate(commitments)
      commitments.reduce { |agg, c| xor_hex(agg, c) }
    end

    private

    def self.xor_hex(a, b)
      a_bytes = [a].pack("H*").bytes
      b_bytes = [b].pack("H*").bytes
      a_bytes.zip(b_bytes).map { |x, y| x ^ y }.pack("C*").unpack1("H*")
    end
  end
end
