# frozen_string_literal: true

module Election
  # Hybrid X25519 + AES-256-GCM "sealed envelope" used to wrap each
  # CEP decryption-key shard at generation time. The recipient (council
  # member) keeps a printed X25519 private key. The DB stores ONLY:
  #
  #   1. the wire-format ciphertext (eph_pub || nonce || ct||tag)
  #   2. SHA-256 of the cleartext share (for tamper-check at submission)
  #
  # Threat properties:
  #   * DB compromise alone reveals NOTHING — the per-shard recipient
  #     private key was never persisted server-side.
  #   * Envelope (paper) compromise alone reveals NOTHING — without the
  #     ciphertext from the DB the attacker cannot reconstruct.
  #   * Both together break exactly one shard. You need 5 shards (and 5
  #     liveness-verified council members) to reconstruct the master.
  #
  # Wire format (single string, fields separated by `$`):
  #
  #   v1$<base64 eph_pub_der>$<base64 iv12>$<base64 ct||tag16>
  #
  # The version prefix lets us migrate the construction later without a
  # data migration — old envelopes still decrypt with the v1 path.
  class ShardEnvelope
    VERSION       = "v1"
    SALT          = "bonvote-shard-envelope-v1"
    INFO          = "shard-key"
    AES_KEY_BYTES = 32   # AES-256
    NONCE_BYTES   = 12   # GCM standard
    TAG_BYTES     = 16

    class DecryptError    < StandardError; end
    class InvalidWireError < StandardError; end

    class << self
      # Mint a fresh X25519 keypair for one shard recipient.
      # The private half is destined for the printed envelope; the
      # public half is what we encrypt against.
      #
      # @return [Hash] { private_key_b64:, public_key_b64: }
      def generate_recipient_keypair
        key = OpenSSL::PKey.generate_key("X25519")
        {
          private_key_b64: Base64.strict_encode64(key.private_to_der),
          public_key_b64:  Base64.strict_encode64(key.public_to_der)
        }
      end

      # Seal `plaintext` to `recipient_public_key_b64`. Returns the wire
      # string suitable for `ElectionKeyShard#shard_value_encrypted`.
      def seal(plaintext, recipient_public_key_b64)
        recipient_pub = OpenSSL::PKey.read(Base64.strict_decode64(recipient_public_key_b64))
        ephemeral     = OpenSSL::PKey.generate_key("X25519")
        shared        = ephemeral.derive(recipient_pub)
        aes_key       = hkdf(shared)

        cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
        cipher.key = aes_key
        iv = SecureRandom.random_bytes(NONCE_BYTES)
        cipher.iv = iv
        ct  = cipher.update(plaintext.to_s) + cipher.final
        tag = cipher.auth_tag(TAG_BYTES)

        [
          VERSION,
          Base64.strict_encode64(ephemeral.public_to_der),
          Base64.strict_encode64(iv),
          Base64.strict_encode64(ct + tag)
        ].join("$")
      ensure
        # best-effort scrub of derived key material
        aes_key = nil
        shared  = nil
      end

      # Open a wire string with the recipient's printed private key.
      # Raises DecryptError on auth-tag failure (tamper or wrong key)
      # or InvalidWireError on structural problems.
      def open(wire, recipient_private_key_b64)
        version, eph_b64, iv_b64, ct_b64 = wire.to_s.split("$", 4)
        raise InvalidWireError, "version=#{version.inspect} not supported" unless version == VERSION
        if [ eph_b64, iv_b64, ct_b64 ].any? { |part| part.nil? || part.empty? }
          raise InvalidWireError, "wire missing parts"
        end

        eph_pub        = OpenSSL::PKey.read(Base64.strict_decode64(eph_b64))
        recipient_priv = OpenSSL::PKey.read(Base64.strict_decode64(recipient_private_key_b64))
        shared         = recipient_priv.derive(eph_pub)
        aes_key        = hkdf(shared)

        ct_and_tag = Base64.strict_decode64(ct_b64)
        if ct_and_tag.bytesize <= TAG_BYTES
          raise InvalidWireError, "ciphertext too short"
        end
        ct  = ct_and_tag.byteslice(0, ct_and_tag.bytesize - TAG_BYTES)
        tag = ct_and_tag.byteslice(ct_and_tag.bytesize - TAG_BYTES, TAG_BYTES)
        iv  = Base64.strict_decode64(iv_b64)

        cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
        cipher.key = aes_key
        cipher.iv  = iv
        cipher.auth_tag = tag
        cipher.update(ct) + cipher.final
      rescue ArgumentError, OpenSSL::PKey::PKeyError => e
        raise InvalidWireError, "envelope parse failed: #{e.class}: #{e.message}"
      rescue OpenSSL::Cipher::CipherError => e
        raise DecryptError, "envelope authentication failed: #{e.message}"
      ensure
        aes_key = nil
        shared  = nil
      end

      private

      def hkdf(ikm)
        OpenSSL::KDF.hkdf(ikm, salt: SALT, info: INFO, length: AES_KEY_BYTES, hash: "SHA256")
      end
    end
  end
end
