# frozen_string_literal: true

# app/services/face_liveness_service.rb
#
# Manages AWS Rekognition Face Liveness sessions.
# Creates sessions for the client-side FaceLivenessDetector component,
# and retrieves results (confidence score + reference image) after completion.
#
# Optimizations (per AWS best practices):
#   - Confidence threshold: 75% (optimized for real-world mobile conditions;
#     100% face-match provides secondary biometric safety net)
#   - Server-side rate limiting (5 attempts per 3 minutes per user)
#   - Audit image capture for admin review
#
# Usage:
#   FaceLivenessService.create_session
#   # => { success: true, session_id: "abc-123" }
#
#   FaceLivenessService.get_results("abc-123")
#   # => { success: true, status: "SUCCEEDED", confidence: 95.2, passed: true, reference_image_bytes: "..." }
#
#   FaceLivenessService.rate_limited?(user_id)
#   # => false
#
class FaceLivenessService
  require "aws-sdk-rekognition"

  LIVENESS_CONFIDENCE_THRESHOLD = 75.0
  MANUAL_REVIEW_THRESHOLD = 65.0  # Gray zone: 65–74% → pass but flag for admin review

  # Rate limiting: max attempts per window
  MAX_ATTEMPTS = 5
  RATE_LIMIT_WINDOW = 3.minutes

  def self.create_session
    new.create_session
  end

  def self.get_results(session_id)
    new.get_results(session_id)
  end

  # Server-side rate limiting using Rails cache
  def self.rate_limited?(user_id)
    key = "liveness_attempts:#{user_id}"
    attempts = Rails.cache.read(key) || []

    # Clean up expired entries
    cutoff = Time.current - RATE_LIMIT_WINDOW
    recent = attempts.select { |t| t > cutoff }

    recent.length >= MAX_ATTEMPTS
  end

  def self.record_attempt!(user_id)
    key = "liveness_attempts:#{user_id}"
    attempts = Rails.cache.read(key) || []

    cutoff = Time.current - RATE_LIMIT_WINDOW
    recent = attempts.select { |t| t > cutoff }
    recent << Time.current

    Rails.cache.write(key, recent, expires_in: RATE_LIMIT_WINDOW)
  end

  def self.clear_attempts!(user_id)
    Rails.cache.delete("liveness_attempts:#{user_id}")
  end

  def create_session
    response = self.class.rekognition_client.create_face_liveness_session({
      settings: {
        audit_images_limit: 4,           # Max frames for human-in-the-loop review of gray-zone scores
        challenge_preferences: [{
          type: "FaceMovementChallenge"   # Faster mode — no flashing lights, better for high-glare environments
        }]
      },
      client_request_token: SecureRandom.uuid
    })

    Rails.logger.info "[FaceLivenessService] Created session: #{response.session_id}"
    { success: true, session_id: response.session_id }
  rescue Aws::Rekognition::Errors::ServiceError => e
    Rails.logger.error "[FaceLivenessService] create_session failed: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  rescue StandardError => e
    Rails.logger.error "[FaceLivenessService] create_session unexpected error: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  end

  def get_results(session_id)
    response = self.class.rekognition_client.get_face_liveness_session_results({
      session_id: session_id
    })

    confidence = response.confidence.to_f
    succeeded  = response.status == "SUCCEEDED"

    # Three-tier decision:
    #   ≥ 75%  → passed (auto-approved)
    #   65–74% → passed but flagged for manual admin review (gray zone)
    #   < 65%  → failed (hard block — likely spoofed or very poor conditions)
    passed       = succeeded && confidence >= MANUAL_REVIEW_THRESHOLD
    needs_review = passed && confidence < LIVENESS_CONFIDENCE_THRESHOLD

    # Extract reference image bytes if available
    ref_bytes = response.reference_image&.s3_object ? nil : response.reference_image&.bytes

    # Collect audit frame bytes for admin review (up to 4)
    audit_bytes = response.audit_images&.map { |img| img.bytes }&.compact || []

    Rails.logger.info "[FaceLivenessService] Session #{session_id}: status=#{response.status}, confidence=#{confidence.round(2)}, passed=#{passed}, needs_review=#{needs_review}"

    {
      success: true,
      session_id: response.session_id,
      status: response.status,
      confidence: confidence.round(2),
      passed: passed,
      needs_review: needs_review,
      reference_image_bytes: ref_bytes,
      audit_image_bytes: audit_bytes,
      threshold: LIVENESS_CONFIDENCE_THRESHOLD
    }
  rescue Aws::Rekognition::Errors::SessionNotFoundException => e
    Rails.logger.error "[FaceLivenessService] Session not found: #{session_id}"
    { success: false, error: "Session not found or expired" }
  rescue Aws::Rekognition::Errors::ServiceError => e
    Rails.logger.error "[FaceLivenessService] get_results failed for #{session_id}: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  end

  # Thread-safe singleton AWS Rekognition client.
  # AWS SDK clients are thread-safe and manage their own HTTP connection pools.
  # One client reused across all requests eliminates per-request instantiation overhead.
  def self.rekognition_client
    @rekognition_client ||= begin
      client_options = {
        region: Rails.application.credentials.dig(:aws, :rekognition, :region) || "us-east-1",
        access_key_id: Rails.application.credentials.dig(:aws, :rekognition, :access_key_id),
        secret_access_key: Rails.application.credentials.dig(:aws, :rekognition, :secret_access_key),
        retry_limit: 3,
        retry_backoff: ->(c) { sleep(2**c.retries * 0.3) }
      }

      ca_bundle = resolve_ca_bundle
      if ca_bundle
        client_options[:ssl_ca_bundle] = ca_bundle
        Rails.logger.info "[FaceLivenessService] Using CA bundle: #{ca_bundle}"
      end

      Aws::Rekognition::Client.new(client_options)
    end
  end

  def self.resolve_ca_bundle
    candidates = [
      ENV["SSL_CERT_FILE"],
      ENV["AWS_CA_BUNDLE"],
      "/opt/homebrew/etc/ca-certificates/cert.pem",
      "/opt/homebrew/etc/openssl@3/cert.pem",
      "/usr/local/etc/openssl@3/cert.pem",
      "/usr/local/etc/ca-certificates/cert.pem",
      "/etc/ssl/cert.pem",
      "/etc/ssl/certs/ca-certificates.crt"
    ].compact

    candidates.find { |path| File.exist?(path) }
  end
  private_class_method :resolve_ca_bundle
end
