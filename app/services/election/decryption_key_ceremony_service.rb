# frozen_string_literal: true

require "secret_sharing"

module Election
  # Generates the CEP final-tally decryption key for a `BonvoteElection`,
  # splits it into 9 Shamir shards (5-of-9 quorum), persists each shard
  # against a CEP council role, and stamps the election with the master
  # key fingerprint so a later reconstruction can be verified before any
  # ciphertext is touched.
  #
  # This is step 1 of the ceremony architecture documented in
  # `memory/project_cep_decryption_ceremony_shards.md`. The downstream
  # pieces — BonID-pubkey-encrypted distribution, recovery UI, and the
  # final reconstruct-and-tally step — consume the rows this service
  # writes.
  #
  # Idempotency: re-running on an election that already has shards is a
  # no-op (returns the existing rows). To rotate, call `#regenerate!`.
  #
  # Trust model: the master key string never leaves this method's stack
  # frame in memory, the database, or logs. We persist:
  #   * each cleartext shard string (placeholder; will be wrapped in
  #     the council member's BonID-pubkey ciphertext during the
  #     distribution step)
  #   * SHA-256 of each shard for tamper-evidence
  #   * SHA-256 of the master itself as the election fingerprint
  class DecryptionKeyCeremonyService
    THRESHOLD    = ElectionKeyShard::QUORUM   # 5
    TOTAL_SHARDS = ElectionKeyShard::ROLES.size # 9
    MASTER_KEY_BYTES = 32                       # 256-bit secret

    class GenerationError    < StandardError; end
    class AlreadyGeneratedError < GenerationError; end

    attr_reader :election

    def self.generate!(election)
      new(election).generate!
    end

    def self.regenerate!(election)
      new(election).regenerate!
    end

    def initialize(election)
      @election = election
    end

    def generate!
      if election.election_key_shards.exists?
        raise AlreadyGeneratedError,
              "Eleksyon #{election.id} gen tan gen kle dechifraj — itilize regenerate!"
      end
      _generate_and_persist!
    end

    def regenerate!
      ElectionKeyShard.transaction do
        election.election_key_shards.destroy_all
        _generate_and_persist!
      end
    end

    private

    def _generate_and_persist!
      master = SecureRandom.hex(MASTER_KEY_BYTES) # 64-char ASCII-safe hex
      shares = SecretSharing.split(master, THRESHOLD, TOTAL_SHARDS)

      raise GenerationError, "Shamir split misyon: #{shares.size} pou #{TOTAL_SHARDS}" unless shares.size == TOTAL_SHARDS

      master_fingerprint = OpenSSL::Digest::SHA256.hexdigest(master)

      created = ElectionKeyShard.transaction do
        rows = ElectionKeyShard::ROLES.zip(shares).map do |role, share|
          ElectionKeyShard.create!(
            election:              election,
            role:                  role,
            shard_value_encrypted: share, # cleartext placeholder until BonID-pubkey wrap lands
            shard_hash:            OpenSSL::Digest::SHA256.hexdigest(share),
            threshold:             THRESHOLD,
            total_shards:          TOTAL_SHARDS
          )
        end

        election.update!(
          decryption_key_fingerprint:  master_fingerprint,
          decryption_key_generated_at: Time.current
        )

        rows
      end

      Rails.logger.info(
        "[DecryptionKeyCeremony] Generated #{created.size} shards for election=#{election.id} " \
        "fingerprint=#{master_fingerprint[0..15]}…"
      )

      # Caller never sees the master itself — only the persisted shards.
      created
    ensure
      master = nil
      shares = nil
    end
  end
end
