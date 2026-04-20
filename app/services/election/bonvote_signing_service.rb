# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

module Election
  # Produces an Ed25519 signature over a receipt payload so verification
  # tablets can confirm authenticity offline.
  #
  # The signing authority is BonVote (not CEP). BonVote follows CEP's
  # protocol; the signature attests "BonVote issued this receipt according
  # to CEP's protocol." If and when CEP formally delegates signing authority
  # or co-signs, that becomes a second, independent attestation — this one
  # stays scoped to what it actually proves.
  #
  # The private key is loaded from encrypted credentials:
  #   Rails.application.credentials.dig(:election, :bonvote_signing_keys, election_id)
  # stored as a base64-encoded 32-byte Ed25519 seed.
  #
  # Phase 1 behavior:
  #   - When the key is present, signs and returns a base64 signature.
  #   - When absent (default today), raises NotConfiguredError. Callers
  #     rescue and skip signing — the receipt still renders, just without a
  #     cryptographic attestation.
  #
  # Verification is symmetric: a tablet app computes the same payload,
  # applies the public key, and accepts only matching signatures.
  class BonvoteSigningService
    class NotConfiguredError < StandardError; end
    class InvalidKeyError    < StandardError; end

    # Signs the canonical JSON of `payload` with the election's private key.
    # Returns base64url-encoded signature bytes.
    def self.sign(election:, payload:)
      new(election: election).sign(payload)
    end

    def self.verify(election:, payload:, signature_b64:, key_id: nil)
      new(election: election).verify(payload, signature_b64, key_id: key_id)
    end

    def initialize(election:)
      @election = election
    end

    def sign(payload)
      key = load_private_key
      # Ed25519 hashes internally (SHA-512 + domain separation per RFC 8032);
      # passing an explicit digest raises "Explicit digest not allowed". We
      # pass nil so OpenSSL uses the Ed25519 native algorithm.
      sig = key.sign(nil, canonical_json(payload))
      Base64.urlsafe_encode64(sig, padding: false)
    end

    # Verifies a signature against the election's public key.
    #
    # When `key_id` is provided (modern receipts), looks the key up via
    # BonvoteKeyRegistry — covers current AND archived keys, so receipts
    # signed under a previous key still verify after rotation.
    #
    # When `key_id` is nil (legacy receipts predating kid), falls back to
    # the current key. Verification simply fails if the key has rotated.
    def verify(payload, signature_b64, key_id: nil)
      pub = lookup_public_key(key_id)
      return false unless pub

      raw = Base64.urlsafe_decode64(signature_b64)
      pub.verify(nil, raw, canonical_json(payload))
    rescue ArgumentError, OpenSSL::PKey::PKeyError
      false
    end

    private

    # Deterministic JSON for signing — sorted keys, no whitespace variance.
    def canonical_json(payload)
      JSON.generate(deep_sort(payload))
    end

    def deep_sort(obj)
      case obj
      when Hash  then obj.keys.sort_by(&:to_s).each_with_object({}) { |k, h| h[k] = deep_sort(obj[k]) }
      when Array then obj.map { |e| deep_sort(e) }
      else obj
      end
    end

    def load_private_key
      seed_b64 = Rails.application.credentials.dig(
        :election, :bonvote_signing_keys, @election.id.to_s.to_sym, :private
      )
      raise NotConfiguredError, "BonVote signing key not set for election #{@election.id}" if seed_b64.blank?

      seed = Base64.decode64(seed_b64)
      raise InvalidKeyError, "Ed25519 seed must be 32 bytes" unless seed.bytesize == 32

      OpenSSL::PKey.new_raw_private_key("ED25519", seed)
    end

    def load_public_key
      pub_b64 = Rails.application.credentials.dig(
        :election, :bonvote_signing_keys, @election.id.to_s.to_sym, :public
      )
      raise NotConfiguredError, "BonVote public key not set for election #{@election.id}" if pub_b64.blank?

      raw = Base64.decode64(pub_b64)
      OpenSSL::PKey.new_raw_public_key("ED25519", raw)
    end

    # Picks the public key to verify against. With a kid we honour it
    # (covers archived keys); without one we fall back to the current key
    # for backwards compatibility with pre-kid receipts.
    def lookup_public_key(key_id)
      key = if key_id.present?
              ::Election::BonvoteKeyRegistry.find_by_key_id(@election, key_id)
            else
              ::Election::BonvoteKeyRegistry.current(@election)
            end
      return nil unless key&.public_key_b64.present?

      OpenSSL::PKey.new_raw_public_key("ED25519", Base64.decode64(key.public_key_b64))
    rescue OpenSSL::PKey::PKeyError
      nil
    end
  end
end
