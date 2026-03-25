# frozen_string_literal: true

# ==========================================================================
# Public endpoint for distributing Ed25519 verification keys.
#
# Partners fetch the public key once, cache it, and use it for
# offline Ed25519 signature verification of BonID QR codes.
#
# No authentication required — this IS the public key.
# ==========================================================================
module Api
  module V1
    class PublicKeysController < ActionController::API
      # GET /api/v1/public_keys/bonid
      #
      # Returns the Ed25519 public key used to sign BonID QR codes.
      # Partners cache this and verify QR signatures offline.
      def bonid
        pub_key = BonidQrSigner.public_key_base64

        if pub_key.blank?
          return render json: {
            error: "Ed25519 public key not configured",
            hint: "Run `rails bonid:generate_ed25519_keypair` and set ENV vars"
          }, status: :service_unavailable
        end

        # Cache-friendly: public key rarely changes
        response.set_header("Cache-Control", "public, max-age=86400") # 24h
        response.set_header("X-Key-Algorithm", "Ed25519")
        response.set_header("X-Issuer", "bonid.ht")

        render json: {
          algorithm: "Ed25519",
          public_key: pub_key,
          encoding: "base64",
          key_fingerprint: Digest::SHA256.hexdigest(Base64.decode64(pub_key)),
          issuer: "bonid.ht",
          usage: "BonID QR code signature verification",
          fetched_at: Time.current.iso8601
        }
      end
    end
  end
end
