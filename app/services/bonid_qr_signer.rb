# frozen_string_literal: true

require "ed25519"
require "base64"

# ==========================================================================
# BonidQrSigner — Ed25519 asymmetric signing for BonID QR code payloads.
#
# Enables true offline verification: partners only need the public key.
# Follows the proven BonTouris pattern (visitor_certificate_presenter.rb).
#
# Signing:   BonidQrSigner.sign(bonid:, expires_at:)
# Verifying: BonidQrSigner.verify(payload)
# Public key: BonidQrSigner.public_key_base64
# ==========================================================================
class BonidQrSigner
  SCHEMA_VERSION = 2
  ISSUER = "bonid.ht"
  TYPE = "BonID"

  # Ordered fields for deterministic canonical string.
  # MUST match between sign() and verify().
  CANONICAL_FIELDS = %w[v iss typ sub ts exp].freeze

  class << self
    # ------------------------------------------------------------------
    # Build a signed QR payload hash.
    #
    #   BonidQrSigner.sign(bonid: "DV-1989-M-SE-P8697XDS", expires_at: 5.years.from_now)
    #   => { "v"=>2, "iss"=>"bonid.ht", "typ"=>"BonID", "sub"=>"DV-...", "ts"=>..., "exp"=>..., "sig"=>"..." }
    # ------------------------------------------------------------------
    def sign(bonid:, expires_at:)
      unsigned = {
        "v"   => SCHEMA_VERSION,
        "iss" => ISSUER,
        "typ" => TYPE,
        "sub" => bonid,
        "ts"  => Time.current.to_i,
        "exp" => expires_at.to_i
      }

      canonical = canonical_string(unsigned)
      sig = signing_key.sign(canonical)

      unsigned.merge("sig" => Base64.urlsafe_encode64(sig, padding: false))
    end

    # ------------------------------------------------------------------
    # Verify a QR payload's Ed25519 signature.
    #
    #   BonidQrSigner.verify(parsed_json_hash)
    #   => :valid | :invalid_signature | :expired | :invalid_payload
    # ------------------------------------------------------------------
    def verify(payload)
      return :invalid_payload unless valid_structure?(payload)
      return :expired if expired?(payload)

      canonical = canonical_string(payload)
      sig_bytes = Base64.urlsafe_decode64(payload["sig"])

      verify_key.verify(sig_bytes, canonical)
      :valid
    rescue Ed25519::VerifyError
      :invalid_signature
    rescue ArgumentError, TypeError
      :invalid_payload
    end

    # ------------------------------------------------------------------
    # Base64-encoded 32-byte public key for the /api/v1/public_keys/bonid endpoint.
    # Partners download this once and cache it for offline verification.
    # ------------------------------------------------------------------
    def public_key_base64
      Base64.strict_encode64(verify_key.to_bytes)
    rescue => e
      Rails.logger.error "Ed25519 public key not available: #{e.message}"
      nil
    end

    private

    def valid_structure?(payload)
      payload.is_a?(Hash) &&
        payload["v"].to_i == SCHEMA_VERSION &&
        payload["iss"] == ISSUER &&
        payload["typ"] == TYPE &&
        payload["sub"].present? &&
        payload["ts"].present? &&
        payload["exp"].present? &&
        payload["sig"].present?
    end

    def expired?(payload)
      Time.at(payload["exp"].to_i) < Time.current
    rescue
      true
    end

    # Deterministic canonical string: "field=value\nfield=value..."
    # Matches the BonTouris pattern in visitor_certificate_presenter.rb (line 152-155)
    def canonical_string(payload)
      CANONICAL_FIELDS.map { |k| "#{k}=#{payload[k]}" }.join("\n")
    end

    def signing_key
      @signing_key ||= Ed25519::SigningKey.new(
        Base64.decode64(
          ENV.fetch("BONID_QR_ED25519_PRIVATE") {
            ENV.fetch("BONID_ED25519_PRIVATE")
          }
        )
      )
    end

    def verify_key
      @verify_key ||= Ed25519::VerifyKey.new(
        Base64.decode64(
          ENV.fetch("BONID_QR_ED25519_PUBLIC") {
            ENV.fetch("BONID_ED25519_PUBLIC")
          }
        )
      )
    end
  end
end
