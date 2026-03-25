# frozen_string_literal: true

# app/services/face_match_service.rb
#
# Compares a citizen's selfie against the face on their ID document
# using AWS Rekognition compare_faces API.
#
# Usage:
#   result = FaceMatchService.call(submission)
#   result[:success]    # => true/false
#   result[:status]     # => "match", "no_match", "no_face_detected", "error"
#   result[:similarity] # => 99.2 (Float, when match/no_match)
#
class FaceMatchService
  require "aws-sdk-rekognition"
  require "net/http"

  SIMILARITY_THRESHOLD = 80.0
  # Minimum confidence that a face was detected in the source (selfie) image.
  # Below this, the image is too blurry/partial for a reliable comparison.
  MIN_FACE_CONFIDENCE = 90.0

  attr_reader :submission

  def initialize(submission)
    @submission = submission
  end

  def self.call(submission)
    new(submission).call
  end

  def call
    # 1. Validate attachments exist
    unless submission.selfie.attached?
      return store_result(status: "error", error_message: "Selfie not attached")
    end

    target_attachment, target_name = resolve_target_image
    unless target_attachment
      return store_result(status: "error", error_message: "No ID document (CIN front or passport) attached")
    end

    # 2. Download image bytes from ActiveStorage
    selfie_bytes = download_blob(submission.selfie)
    target_bytes = download_blob(target_attachment)

    unless selfie_bytes && target_bytes
      return store_result(status: "error", error_message: "Failed to download image bytes from storage")
    end

    # 3. Call AWS Rekognition compare_faces (threshold 0 to get actual similarity)
    response = compare_faces_aws(selfie_bytes, target_bytes)

    # 4. Check source face quality — reject if selfie face detection is too low
    #    (blurry, partial face, obstructed). This prevents unreliable comparisons.
    source_confidence = response.source_image_face&.confidence&.round(2)
    if source_confidence && source_confidence < MIN_FACE_CONFIDENCE
      return store_result(
        status: "no_match",
        similarity: 0.0,
        threshold: SIMILARITY_THRESHOLD,
        source_image: "selfie",
        target_image: target_name,
        source_face_confidence: source_confidence,
        error_message: "Selfie face detection confidence too low (#{source_confidence}%, minimum #{MIN_FACE_CONFIDENCE}%)"
      )
    end

    # 5. Process response — we pass threshold 0 to the API so face_matches
    #    always contains results with their real similarity score.
    #    We then check against SIMILARITY_THRESHOLD ourselves.
    if response.face_matches.any?
      best_match = response.face_matches.max_by(&:similarity)
      actual_similarity = best_match.similarity.round(2)

      if actual_similarity >= SIMILARITY_THRESHOLD
        store_result(
          status: "match",
          similarity: actual_similarity,
          threshold: SIMILARITY_THRESHOLD,
          source_image: "selfie",
          target_image: target_name,
          source_face_confidence: response.source_image_face&.confidence&.round(2),
          target_face_confidence: best_match.face&.confidence&.round(2)
        )
      else
        store_result(
          status: "no_match",
          similarity: actual_similarity,
          threshold: SIMILARITY_THRESHOLD,
          source_image: "selfie",
          target_image: target_name,
          source_face_confidence: response.source_image_face&.confidence&.round(2),
          target_face_confidence: best_match.face&.confidence&.round(2)
        )
      end
    elsif response.unmatched_faces.any?
      # Faces detected but no comparison data available
      highest_unmatched = response.unmatched_faces.max_by(&:confidence)
      store_result(
        status: "no_match",
        similarity: 0.0,
        threshold: SIMILARITY_THRESHOLD,
        source_image: "selfie",
        target_image: target_name,
        source_face_confidence: response.source_image_face&.confidence&.round(2),
        target_face_confidence: highest_unmatched&.confidence&.round(2)
      )
    else
      # No faces detected in the target image
      store_result(
        status: "no_face_detected",
        source_image: "selfie",
        target_image: target_name,
        source_face_confidence: response.source_image_face&.confidence&.round(2),
        error_message: "No face detected in the ID document image"
      )
    end
  rescue Aws::Rekognition::Errors::InvalidParameterException => e
    handle_aws_error(e, target_name)
  rescue Aws::Rekognition::Errors::ServiceError => e
    handle_aws_error(e, target_name)
  rescue StandardError => e
    Rails.logger.error "[FaceMatchService] Unexpected error for submission #{submission.id}: #{e.class} - #{e.message}"
    store_result(status: "error", error_message: "Unexpected error: #{e.message.truncate(200)}")
  end

  private

  # Uses similarity_threshold 0 so AWS returns all matches with actual similarity scores.
  def compare_faces_aws(source_bytes, target_bytes)
    params = {
      source_image: { bytes: source_bytes },
      target_image: { bytes: target_bytes },
      similarity_threshold: 0
    }

    self.class.rekognition_client.compare_faces(params)
  end

  # Determines which ID document to compare against (CIN front preferred, then passport)
  def resolve_target_image
    if submission.cin_front.attached?
      [submission.cin_front, "cin_front"]
    elsif submission.passport.attached?
      [submission.passport, "passport"]
    else
      [nil, nil]
    end
  end

  # Downloads the blob bytes from ActiveStorage (works with both Disk and S3/Tigris)
  # Falls back to URL-based download if direct blob.download fails.
  def download_blob(attachment)
    blob = attachment.blob
    Rails.logger.info "[FaceMatchService] Downloading blob ##{blob.id} (#{blob.filename}, #{blob.byte_size} bytes, service: #{blob.service_name})"

    # Try direct download first
    begin
      bytes = blob.download
      return bytes if bytes.present?
    rescue ActiveStorage::FileNotFoundError => e
      Rails.logger.warn "[FaceMatchService] Direct download failed for blob ##{blob.id} (#{blob.key}): #{e.message}. Trying URL fallback..."
    rescue Errno::ENOENT => e
      Rails.logger.warn "[FaceMatchService] Disk file missing for blob ##{blob.id} (#{blob.key}): #{e.message}. Trying URL fallback..."
    rescue StandardError => e
      Rails.logger.warn "[FaceMatchService] Direct download error for blob ##{blob.id}: #{e.class} - #{e.message}. Trying URL fallback..."
    end

    # Fallback: download via service URL (works when files are on remote storage like Tigris/S3)
    download_blob_via_url(blob)
  end

  # Downloads blob bytes by fetching the service URL
  def download_blob_via_url(blob)
    url = blob.url(expires_in: 5.minutes)
    Rails.logger.info "[FaceMatchService] Fallback: downloading blob ##{blob.id} via URL"

    uri = URI.parse(url)
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      Rails.logger.info "[FaceMatchService] URL fallback succeeded for blob ##{blob.id} (#{response.body.bytesize} bytes)"
      response.body
    else
      Rails.logger.error "[FaceMatchService] URL fallback failed for blob ##{blob.id}: HTTP #{response.code}"
      nil
    end
  rescue StandardError => e
    Rails.logger.error "[FaceMatchService] URL fallback error for blob ##{blob.id}: #{e.class} - #{e.message}"
    nil
  end

  # Stores face match results in the submission's metadata JSONB column
  def store_result(status:, similarity: nil, threshold: nil, source_image: nil,
                   target_image: nil, source_face_confidence: nil,
                   target_face_confidence: nil, error_message: nil)
    face_match_data = {
      "status" => status,
      "similarity" => similarity,
      "threshold" => threshold || SIMILARITY_THRESHOLD,
      "source_image" => source_image,
      "target_image" => target_image,
      "matched_at" => Time.current.iso8601,
      "source_face_confidence" => source_face_confidence,
      "target_face_confidence" => target_face_confidence,
      "error_message" => error_message
    }.compact

    # Merge into existing metadata to preserve other keys
    current_metadata = submission.metadata || {}
    updated_metadata = current_metadata.merge("face_match" => face_match_data)

    submission.update_column(:metadata, updated_metadata)

    Rails.logger.info "[FaceMatchService] Submission ##{submission.id}: status=#{status}, similarity=#{similarity}"

    { success: status.in?(%w[match no_match no_face_detected]), **face_match_data.symbolize_keys }
  end

  def handle_aws_error(error, target_name)
    error_status = if error.message.downcase.include?("no face") || error.is_a?(Aws::Rekognition::Errors::InvalidParameterException)
                     "no_face_detected"
                   else
                     "error"
                   end

    Rails.logger.error "[FaceMatchService] AWS error for submission #{submission.id}: #{error.class} - #{error.message}"

    store_result(
      status: error_status,
      source_image: "selfie",
      target_image: target_name,
      error_message: "AWS Rekognition: #{error.message.truncate(200)}"
    )
  end

  # Thread-safe singleton AWS Rekognition client with retry/backoff.
  # AWS SDK clients are thread-safe and manage their own HTTP connection pools.
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
        Rails.logger.info "[FaceMatchService] Using CA bundle: #{ca_bundle}"
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
