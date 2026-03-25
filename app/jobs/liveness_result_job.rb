# frozen_string_literal: true

# app/jobs/liveness_result_job.rb
#
# Async liveness result fetching for Haiti's low-bandwidth networks.
#
# Instead of making the citizen wait on a synchronous AWS API call
# (which can take 2–10s on slow connections), this job:
#   1. Fetches results from AWS Rekognition in the background
#   2. Uploads the reference image as an ActiveStorage blob
#   3. Backgrounds audit frame uploads for gray-zone cases
#   4. Caches the final result for the polling endpoint to pick up
#
# The frontend polls `/liveness_status` every 2s until the result
# is ready (max 30s). Even if the user's connection drops mid-poll,
# the job still completes and the result is cached for 10 minutes.
#
class LivenessResultJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 5.seconds, attempts: 2
  discard_on ActiveJob::DeserializationError

  # @param session_id [String] AWS liveness session ID
  # @param user_id [Integer] citizen's user ID (for rate limit management)
  def perform(session_id, user_id)
    result = FaceLivenessService.get_results(session_id)
    cache_key = "liveness_result:#{session_id}"

    if result[:success] && result[:passed]
      FaceLivenessService.clear_attempts!(user_id)

      # Upload reference image as ActiveStorage blob
      blob_signed_id = nil
      if result[:reference_image_bytes].present?
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(result[:reference_image_bytes]),
          filename: "liveness_selfie_#{session_id[0..7]}.jpg",
          content_type: "image/jpeg"
        )
        blob_signed_id = blob.signed_id
      end

      # Background audit frames for gray-zone cases (65–74% confidence)
      if result[:needs_review] && result[:audit_image_bytes].present?
        audit_cache_key = "audit_bytes:#{session_id}"
        Rails.cache.write(audit_cache_key, result[:audit_image_bytes], expires_in: 30.minutes)
        AuditBlobUploadJob.perform_later(session_id, audit_cache_key)
      end

      Rails.cache.write(cache_key, {
        status: "completed",
        passed: true,
        result_status: result[:status],
        confidence: result[:confidence],
        needs_review: result[:needs_review] || false,
        blob_signed_id: blob_signed_id
      }, expires_in: 10.minutes)

      Rails.logger.info "[LivenessResultJob] Session #{session_id[0..7]} passed (#{result[:confidence]}%)"
    elsif result[:success]
      # Liveness check failed (below threshold)
      FaceLivenessService.record_attempt!(user_id)

      Rails.cache.write(cache_key, {
        status: "completed",
        passed: false,
        result_status: result[:status],
        confidence: result[:confidence]
      }, expires_in: 10.minutes)

      Rails.logger.info "[LivenessResultJob] Session #{session_id[0..7]} failed (#{result[:confidence]}%)"
    else
      # AWS error
      Rails.cache.write(cache_key, {
        status: "error",
        error: result[:error]
      }, expires_in: 10.minutes)

      Rails.logger.error "[LivenessResultJob] Session #{session_id[0..7]} error: #{result[:error]}"
    end
  end
end
