# frozen_string_literal: true

require "ed25519"
require "base64"
require "digest"

# ==========================================================================
# BonGouv::ReceiptSigner — Ed25519 digital seal for DGI payment receipts.
#
# Turns "Dokiman Otantik — BonGouv" from a visual badge into a
# cryptographically verifiable proof of payment.
#
# How it works:
#   1. Canonicalizes the payment data into a deterministic string
#   2. Signs the canonical string with BonGouv's Ed25519 private key
#   3. Generates a verification token (short URL-safe ID)
#   4. Produces a QR code containing the verification URL + signed payload
#
# Tamper-proof: If any field (amount, date, NIF, etc.) is altered,
#   the signature check fails.
#
# Non-repudiation: The DGI cannot deny receiving the payment —
#   the signature is uniquely tied to the payment record.
#
# Usage:
#   seal = BonGouv::ReceiptSigner.sign(payment)
#   seal[:token]          # => "bGv_A3F29E1B7C"
#   seal[:signature]      # => Base64-encoded Ed25519 signature
#   seal[:qr_png_base64]  # => Base64-encoded PNG for the receipt QR
#   seal[:verify_url]     # => "https://bongouv.ht/v/bGv_A3F29E1B7C"
#   seal[:payload]        # => canonical JSON payload (for offline verify)
# ==========================================================================
module Bongouv
  class ReceiptSigner
    SCHEMA_VERSION = 1
    ISSUER = "bongouv.ht"
    TYPE = "DGI-RECEIPT"
    VERIFY_BASE_URL = ENV.fetch("BONGOUV_VERIFY_URL", "https://bongouv.ht/v")

    # Ordered fields for deterministic canonical string.
    # MUST match between sign() and verify().
    CANONICAL_FIELDS = %w[v iss typ oid amt fee tot cur mth nif sub ts].freeze

    class << self
      # ----------------------------------------------------------------
      # Sign a DgiPayment → returns seal hash with token, sig, QR, URL.
      # ----------------------------------------------------------------
      def sign(payment)
        payload = build_payload(payment)
        canonical = canonical_string(payload)
        sig = signing_key.sign(canonical)
        sig_b64 = Base64.urlsafe_encode64(sig, padding: false)

        # Short verification token: "bGv_" prefix + first 10 hex of SHA256
        token = generate_token(payment)

        # Generate the verification QR code
        verify_url = "#{VERIFY_BASE_URL}/#{token}"
        qr_data = { url: verify_url, sig: sig_b64, v: SCHEMA_VERSION }.to_json
        qr_png_base64 = generate_seal_qr(qr_data)

        # Store signature + token + QR on the payment record
        payment.update_columns(
          provider_response: (payment.provider_response || {}).merge(
            "bongouv_seal" => {
              "token"          => token,
              "signature"      => sig_b64,
              "signed_at"      => Time.current.iso8601,
              "version"        => SCHEMA_VERSION,
              "verify_url"     => verify_url,
              "qr_png_base64"  => qr_png_base64
            }
          )
        )

        {
          token: token,
          signature: sig_b64,
          payload: payload,
          qr_png_base64: qr_png_base64,
          verify_url: verify_url,
          signed_at: Time.current
        }
      end

      # ----------------------------------------------------------------
      # Verify a payment's seal. Returns :valid, :invalid, or :not_signed.
      # ----------------------------------------------------------------
      def verify(payment)
        seal = payment.provider_response&.dig("bongouv_seal")
        return :not_signed unless seal.present?

        payload = build_payload(payment)
        canonical = canonical_string(payload)
        sig_bytes = Base64.urlsafe_decode64(seal["signature"])

        verify_key.verify(sig_bytes, canonical)
        :valid
      rescue Ed25519::VerifyError
        :invalid
      rescue ArgumentError, TypeError
        :invalid
      end

      # ----------------------------------------------------------------
      # Verify from a token (for the public verification endpoint).
      # Returns { status:, payment:, payload: } or { status: :not_found }.
      # ----------------------------------------------------------------
      def verify_by_token(token)
        payment = find_payment_by_token(token)
        return { status: :not_found } unless payment

        result = verify(payment)
        {
          status: result,
          payment: payment,
          payload: result == :valid ? build_payload(payment) : nil
        }
      end

      # ----------------------------------------------------------------
      # Public key (Base64) for offline verification by auditors/banks.
      # ----------------------------------------------------------------
      def public_key_base64
        Base64.strict_encode64(verify_key.to_bytes)
      rescue => e
        Rails.logger.error "BonGouv Ed25519 public key not available: #{e.message}"
        nil
      end

      private

      # Build the canonical payload from a payment.
      def build_payload(payment)
        {
          "v"   => SCHEMA_VERSION,
          "iss" => ISSUER,
          "typ" => TYPE,
          "oid" => payment.order_id,
          "amt" => payment.amount_htg.to_s,
          "fee" => payment.fee_htg.to_s,
          "tot" => payment.total_htg.to_s,
          "cur" => payment.currency || "HTG",
          "mth" => payment.payment_method,
          "nif" => payment.verification_record&.data&.dig("identification", "nif") ||
                   payment.verification_record&.data&.dig("personne", "numero_cin") || "",
          "sub" => payment.user.bonid,
          "ts"  => (payment.paid_at || payment.created_at).to_i
        }
      end

      # Deterministic canonical string: "field=value\nfield=value..."
      # Same pattern as BonidQrSigner for consistency.
      def canonical_string(payload)
        CANONICAL_FIELDS.map { |k| "#{k}=#{payload[k]}" }.join("\n")
      end

      # Short token: "bGv_" + truncated hex hash of order_id
      def generate_token(payment)
        hash = Digest::SHA256.hexdigest("#{payment.order_id}:#{payment.user_id}:#{payment.created_at.to_i}")
        "bGv_#{hash[0..11].upcase}"
      end

      # Find a payment by its seal token (stored in provider_response JSONB).
      def find_payment_by_token(token)
        DgiPayment.where("provider_response -> 'bongouv_seal' ->> 'token' = ?", token).first
      end

      # Generate a QR PNG in BonGouv blue, same style as BonID QRs.
      def generate_seal_qr(data)
        qr = RQRCode::QRCode.new(data, level: :m)
        png = qr.as_png(
          bit_depth: 1,
          border_modules: 3,
          color_mode: ChunkyPNG::COLOR_RGB,
          color: ChunkyPNG::Color.from_hex("#00209F"),
          fill: ChunkyPNG::Color::WHITE,
          module_px_size: 5,
          size: 240
        )
        Base64.strict_encode64(png.to_s)
      rescue => e
        Rails.logger.error "BonGouv QR generation failed: #{e.message}"
        nil
      end

      # Uses the same Ed25519 key pair as BonID QR signing.
      # In production, you may want separate keys: BONGOUV_ED25519_PRIVATE/PUBLIC.
      def signing_key
        @signing_key ||= Ed25519::SigningKey.new(
          Base64.decode64(
            ENV.fetch("BONGOUV_ED25519_PRIVATE") {
              ENV.fetch("BONID_QR_ED25519_PRIVATE") {
                ENV.fetch("BONID_ED25519_PRIVATE")
              }
            }
          )
        )
      end

      def verify_key
        @verify_key ||= Ed25519::VerifyKey.new(
          Base64.decode64(
            ENV.fetch("BONGOUV_ED25519_PUBLIC") {
              ENV.fetch("BONID_QR_ED25519_PUBLIC") {
                ENV.fetch("BONID_ED25519_PUBLIC")
              }
            }
          )
        )
      end
    end
  end
end
