# frozen_string_literal: true

require "ed25519"
require "base64"

module Election
  # Ed25519-signed QR backup payload for a single CEP decryption-key
  # shard. Mirrors the BonidQrSigner pattern (canonical-string → sign)
  # so a council member's printed QR can be verified offline by any
  # device that holds the platform public key.
  #
  # IMPORTANT: the QR payload contains the cleartext shard share.
  # The signature is for INTEGRITY ("this QR really came from us at
  # generation time"), not confidentiality. The QR is meant to live
  # in a physical safe — DO NOT email or upload it.
  #
  # Reuses the BONID Ed25519 keypair (env: BONID_QR_ED25519_PRIVATE /
  # BONID_QR_ED25519_PUBLIC, with BONID_ED25519_* fallback) so we don't
  # introduce another key to rotate. The TYPE field ("ShardBackup")
  # stops a verifier from accepting a BonID-issuance QR as a shard.
  class ShardQrSigner
    SCHEMA_VERSION = 1
    ISSUER         = "bonvote.ht"
    TYPE           = "ShardBackup"

    # Ordered fields for deterministic canonical string. MUST match
    # between sign() and verify().
    CANONICAL_FIELDS = %w[v iss typ election_id shard_role shard_value ts].freeze

    class << self
      # Build a signed payload hash. Caller renders the JSON into a QR
      # via `rqrcode` and prints with the council member's envelope.
      def sign(election_id:, shard_role:, shard_value:)
        unsigned = {
          "v"           => SCHEMA_VERSION,
          "iss"         => ISSUER,
          "typ"         => TYPE,
          "election_id" => election_id.to_s,
          "shard_role"  => shard_role.to_s,
          "shard_value" => shard_value.to_s,
          "ts"          => Time.current.to_i
        }
        sig = signing_key.sign(canonical_string(unsigned))
        unsigned.merge("sig" => Base64.urlsafe_encode64(sig, padding: false))
      end

      # Verify a parsed payload. Returns one of:
      #   :valid | :invalid_signature | :invalid_payload
      def verify(payload)
        return :invalid_payload unless valid_structure?(payload)
        sig_bytes = Base64.urlsafe_decode64(payload["sig"])
        verify_key.verify(sig_bytes, canonical_string(payload))
        :valid
      rescue Ed25519::VerifyError
        :invalid_signature
      rescue ArgumentError, TypeError
        :invalid_payload
      end

      private

      def valid_structure?(p)
        p.is_a?(Hash) &&
          p["v"].to_i == SCHEMA_VERSION &&
          p["iss"] == ISSUER &&
          p["typ"] == TYPE &&
          CANONICAL_FIELDS.all? { |f| p[f].to_s != "" } &&
          p["sig"].present?
      end

      def canonical_string(payload)
        CANONICAL_FIELDS.map { |k| "#{k}=#{payload[k]}" }.join("\n")
      end

      def signing_key
        @signing_key ||= Ed25519::SigningKey.new(
          Base64.decode64(
            ENV.fetch("BONID_QR_ED25519_PRIVATE") { ENV.fetch("BONID_ED25519_PRIVATE") }
          )
        )
      end

      def verify_key
        @verify_key ||= Ed25519::VerifyKey.new(
          Base64.decode64(
            ENV.fetch("BONID_QR_ED25519_PUBLIC") { ENV.fetch("BONID_ED25519_PUBLIC") }
          )
        )
      end
    end
  end
end
