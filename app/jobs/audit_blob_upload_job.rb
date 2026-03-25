# frozen_string_literal: true

# app/jobs/audit_blob_upload_job.rb
#
# Backgrounds the upload of liveness audit images (gray-zone cases only).
# Runs after liveness_results returns — the user is still filling Step 2/3,
# so there's time before the form is submitted in `create`.
#
# Stores completed blob IDs in Rails.cache so `create` can attach them
# to the submission.
#
class AuditBlobUploadJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 5.seconds, attempts: 2
  discard_on ActiveJob::DeserializationError

  # @param session_id [String] AWS liveness session ID (used as cache key namespace)
  # @param cache_key [String] Rails.cache key holding the raw image bytes array
  def perform(session_id, cache_key)
    image_bytes_array = Rails.cache.read(cache_key)

    unless image_bytes_array.present?
      Rails.logger.warn "[AuditBlobUploadJob] No cached bytes for session #{session_id[0..7]}, skipping."
      return
    end

    blob_ids = image_bytes_array.each_with_index.map do |bytes, i|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(bytes),
        filename: "liveness_audit_#{session_id[0..7]}_#{i}.jpg",
        content_type: "image/jpeg"
      )
      blob.id
    end

    # Store blob IDs for pickup by the `create` action
    Rails.cache.write("audit_blob_ids:#{session_id}", blob_ids, expires_in: 30.minutes)

    # Clean up raw bytes from cache
    Rails.cache.delete(cache_key)

    Rails.logger.info "[AuditBlobUploadJob] Uploaded #{blob_ids.size} audit blobs for session #{session_id[0..7]}: #{blob_ids}"
  end
end
