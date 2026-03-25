# app/controllers/api/v1/certificates_controller.rb
#
# Public certificate verification endpoints — NO authentication required.
#
# A partner (embassy, consulate, employer) who received a crime certificate
# from a citizen can independently verify its authenticity using:
#
#   1. POST /api/v1/certificates/verify
#      Provide the certificate fields + signature → we confirm it's genuine
#      and untampered using RSASSA-PSS / HMAC-SHA256.
#
#   2. GET /api/v1/certificates/public_key
#      Returns the RSA-2048 public key PEM so partners can verify offline.
#      This URL is embedded in every certificate's `digital_signature.public_key_url`.
#
# These endpoints are intentionally public so that:
#   - Any embassy officer can verify a certificate without needing a BonID partner account
#   - Verification works even if the BonID API is temporarily unavailable
#   - The public key can be cached by partners for offline use

module Api
  module V1
    class CertificatesController < ActionController::API
      # === Rate limiting (basic — no auth so we limit by IP) ===
      RATE_LIMIT = 200
      WINDOW     = 15.minutes

      before_action :enforce_rate_limit!, only: [:verify]

      # POST /api/v1/certificates/verify
      #
      # Verifies a certificate signature received from a citizen.
      # Partners call this to confirm the certificate was genuinely issued by PNH
      # and has not been tampered with since issuance.
      #
      # Request body (JSON):
      #   {
      #     "certificate_id": "A3F8B2C1D4E5F607",
      #     "report_id":      "PNH-DDO-HOMO-20260222-4BF813-RYO",
      #     "case_number":    "BON-CASE-2026-AB1CD2",
      #     "issued_at":      "2026-02-22T10:30:00Z",
      #     "partner_id":     42,
      #     "algorithm":      "RSASSA-PSS",
      #     "signature_value": "<base64-encoded signature>"
      #   }
      #
      # Response:
      #   { valid: true/false, algorithm: "RSASSA-PSS", report_id: "...", verified_at: "..." }
      def verify
        start_time = Time.current

        body = parse_request_body
        return unless body

        certificate_id  = body["certificate_id"].to_s.strip
        report_id       = body["report_id"].to_s.strip
        case_number     = body["case_number"].to_s.strip
        issued_at       = body["issued_at"].to_s.strip
        partner_id      = body["partner_id"].to_i
        algorithm       = body["algorithm"].to_s.strip
        signature_value = body["signature_value"].to_s.strip

        # Validate required fields
        missing = []
        missing << "certificate_id"  if certificate_id.blank?
        missing << "report_id"       if report_id.blank?
        missing << "issued_at"       if issued_at.blank?
        missing << "algorithm"       if algorithm.blank?
        missing << "signature_value" if signature_value.blank?

        if missing.any?
          return render json: {
            valid:   false,
            error:   "Missing required fields: #{missing.join(', ')}",
            code:    422
          }, status: :unprocessable_entity
        end

        # Reconstruct the canonical payload (must match CrimeCertificateService#generate_digital_signature)
        canonical = {
          case_number:    case_number,
          certificate_id: certificate_id,
          issued_at:      issued_at,
          partner_id:     partner_id,
          report_id:      report_id
        }.to_json

        valid = case algorithm.upcase
                when "RSASSA-PSS"
                  verify_rsa_pss(canonical, signature_value)
                when "HMAC-SHA256"
                  verify_hmac(canonical, signature_value)
                else
                  return render json: {
                    valid:  false,
                    error:  "Unsupported algorithm: #{algorithm}. Supported: RSASSA-PSS, HMAC-SHA256",
                    code:   422
                  }, status: :unprocessable_entity
                end

        # Optionally cross-reference the report_id in our database
        report_exists = IncidentReport.exists?(report_id: report_id)

        duration = ((Time.current - start_time) * 1000).round(2)
        Rails.logger.info("[CertificatesController#verify] algorithm=#{algorithm} valid=#{valid} report_id=#{report_id} duration_ms=#{duration}")

        render json: {
          valid:          valid,
          algorithm:      algorithm,
          certificate_id: certificate_id,
          report_id:      report_id,
          report_found:   report_exists,
          verified_at:    Time.current.iso8601,
          message:        valid ? "Certificate signature is valid. This document was issued by PNH." :
                                  "Certificate signature is INVALID. This document may have been tampered with.",
          issuer:         "Police Nationale d'Haïti (PNH) — Direction Centrale de la Police Judiciaire (DCPJ)",
          public_key_url: api_v1_certificate_public_key_url
        }, status: :ok

      rescue => e
        Rails.logger.error("[CertificatesController#verify] #{e.class}: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
        render json: { valid: false, error: "Verification failed: #{e.message}", code: 500 },
               status: :internal_server_error
      end

      # GET /api/v1/certificates/public_key
      #
      # Returns the RSA-2048 public key PEM for offline certificate verification.
      # Embedded in every certificate's `digital_signature.public_key_url` field.
      # Partners can cache this key and verify certificates without calling our API.
      #
      # Response: text/plain — PEM-encoded RSA public key
      def public_key
        pem = Rails.application.credentials.dig(:bonid, :rsa_public_key)

        if pem.blank?
          return render plain: "# RSA public key not yet configured\n",
                        content_type: "text/plain",
                        status: :not_found
        end

        # Cache-friendly: public key rarely changes
        response.set_header("Cache-Control", "public, max-age=86400") # 24h
        response.set_header("X-Key-Algorithm", "RSA-2048")
        response.set_header("X-Issuer", "PNH-DCPJ-Digital-Unit")

        render plain: pem.strip, content_type: "text/plain", status: :ok
      end

      private

      # Verify RSASSA-PSS signature using the stored RSA public key
      def verify_rsa_pss(canonical, signature_b64)
        pem = Rails.application.credentials.dig(:bonid, :rsa_public_key)
        return false if pem.blank?

        public_key      = OpenSSL::PKey::RSA.new(pem)
        signature_bytes = Base64.strict_decode64(signature_b64)
        digest          = OpenSSL::Digest::SHA256.new

        public_key.verify_pss(digest, signature_bytes, canonical,
                              salt_length: :digest,
                              mgf1_hash:   OpenSSL::Digest::SHA256.new)
      rescue OpenSSL::PKey::RSAError, ArgumentError => e
        Rails.logger.warn("[CertificatesController] RSA verify failed: #{e.message}")
        false
      end

      # Verify HMAC-SHA256 signature (legacy fallback certificates)
      def verify_hmac(canonical, signature_hex)
        secret    = Rails.application.credentials.dig(:bonid, :signature_secret) || "default_secret"
        expected  = OpenSSL::HMAC.hexdigest("SHA256", secret, canonical)
        # Constant-time comparison to prevent timing attacks
        ActiveSupport::SecurityUtils.secure_compare(expected, signature_hex)
      rescue => e
        Rails.logger.warn("[CertificatesController] HMAC verify failed: #{e.message}")
        false
      end

      def parse_request_body
        body = request.body.read
        JSON.parse(body)
      rescue JSON::ParserError => e
        render json: { valid: false, error: "Invalid JSON: #{e.message}", code: 400 },
               status: :bad_request
        nil
      end

      def enforce_rate_limit!
        ip_key = "cert_verify:#{request.remote_ip}"
        count  = Rails.cache.read(ip_key).to_i
        if count >= RATE_LIMIT
          render json: {
            valid:   false,
            error:   "Rate limit exceeded. Try again in 15 minutes.",
            code:    429
          }, status: :too_many_requests
        else
          Rails.cache.write(ip_key, count + 1, expires_in: WINDOW)
        end
      end
    end
  end
end
