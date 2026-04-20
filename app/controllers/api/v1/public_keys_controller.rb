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

      # GET /api/v1/public_keys/bongouv
      #
      # Returns the Ed25519 public key used to sign BonGouv receipts.
      # Banks, auditors, and DGI agents cache this for offline verification.
      def bongouv
        pub_key = Bongouv::ReceiptSigner.public_key_base64

        if pub_key.blank?
          return render json: {
            error: "BonGouv Ed25519 public key not configured",
            hint: "Set BONGOUV_ED25519_PUBLIC or fall back to BONID_ED25519_PUBLIC"
          }, status: :service_unavailable
        end

        response.set_header("Cache-Control", "public, max-age=86400")
        response.set_header("X-Key-Algorithm", "Ed25519")
        response.set_header("X-Issuer", "bongouv.ht")

        render json: {
          algorithm: "Ed25519",
          public_key: pub_key,
          encoding: "base64",
          key_fingerprint: Digest::SHA256.hexdigest(Base64.decode64(pub_key)),
          issuer: "bongouv.ht",
          usage: "BonGouv DGI receipt signature verification",
          fetched_at: Time.current.iso8601
        }
      end

      # GET /api/v1/elections/:id/bonvote_public_key
      #
      # Returns the BonVote signing key(s) for a specific election. The
      # response carries the current key plus every archived key so an
      # offline verifier can reconstruct the trust chain for any historical
      # receipt — `kid` on the receipt → matching key in this response.
      #
      # No authentication required: this IS the public key bundle. Cache
      # for 1 hour rather than 24h because key rotation should propagate
      # quickly enough to halt forged receipts after a private-key leak.
      def bonvote_election
        election = BonvoteElection.find_by(id: params[:id])
        return render(json: { error: "Election not found" }, status: :not_found) if election.nil?

        ::Election::BonvoteKeyRegistry.sync!(election) # mirror credentials → DB if needed
        keys = ::Election::BonvoteKeyRegistry.all(election)

        if keys.empty?
          return render json: {
            error: "BonVote public key not configured for election #{election.id}"
          }, status: :service_unavailable
        end

        current = keys.first
        archived = keys.drop(1)

        response.set_header("Cache-Control", "public, max-age=3600") # 1h
        response.set_header("X-Key-Algorithm", "Ed25519")
        response.set_header("X-Issuer", "bonvote.ht")

        render json: {
          algorithm:    "Ed25519",
          encoding:     "base64",
          issuer:       "bonvote.ht",
          usage:        "BonVote voter-receipt signature verification",
          election: {
            id:    election.id,
            title: election.title,
            round: election.round,
            status: election.status
          },
          current: current.to_h.merge(
            key_fingerprint: Digest::SHA256.hexdigest(Base64.decode64(current.public_key_b64))
          ),
          archived: archived.map { |k|
            k.to_h.merge(
              key_fingerprint: Digest::SHA256.hexdigest(Base64.decode64(k.public_key_b64))
            )
          },
          payload_spec: "https://#{request.host}/spec/receipt-v1",
          fetched_at:   Time.current.iso8601
        }
      end
    end
  end
end
