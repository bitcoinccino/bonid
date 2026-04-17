# frozen_string_literal: true

# Election::VoterFaceMatchService
#
# The gate that turns "a live face passed FaceLiveness" into "a live face
# that is the same person who enrolled." Without this check, a citizen can
# let someone else sit in front of their phone: liveness passes (real human,
# real movement), but the vote ends up cast under the logged-in BonID.
#
# It compares two images via AWS Rekognition CompareFaces:
#
#   source = the liveness selfie captured seconds ago by FaceLiveness
#            (uploaded as an ActiveStorage blob by LivenessResultJob)
#
#   target = the enrolled selfie stored on the citizen's approved
#            IdentitySubmission (the face ONI validated against the CIN/
#            passport during KYC — the anchor behind VoterEligibilityRecord
#            #biometric_fingerprint)
#
# Similarity threshold matches the KYC path (80%) so a voter who can log in
# can also vote — no stricter bar than the identity they already proved.
#
# Fails CLOSED on any error: AWS exception, missing selfie, missing enrolled
# face, invalid blob signed_id. Voting integrity is worth more than the
# edge-case UX of a broken AWS call.
#
module Election
  class VoterFaceMatchService
    SIMILARITY_THRESHOLD = 80.0
    MIN_FACE_CONFIDENCE  = 90.0

    Result = Struct.new(:matched, :similarity, :status, :error_message,
                        keyword_init: true) do
      def matched?
        matched == true
      end
    end

    # @param user [User] the logged-in citizen
    # @param liveness_blob_signed_id [String] signed_id of the liveness
    #   selfie blob (what the form calls `liveness_session_id`, written by
    #   LivenessResultJob as `blob.signed_id`)
    def self.call(user:, liveness_blob_signed_id:)
      new(user: user, liveness_blob_signed_id: liveness_blob_signed_id).call
    end

    def initialize(user:, liveness_blob_signed_id:)
      @user = user
      @liveness_blob_signed_id = liveness_blob_signed_id
    end

    def call
      return fail_closed("missing_liveness_blob") if @liveness_blob_signed_id.blank?

      liveness_blob = ActiveStorage::Blob.find_signed(@liveness_blob_signed_id)
      return fail_closed("invalid_liveness_blob") unless liveness_blob

      submission = approved_submission
      return fail_closed("no_enrolled_submission") unless submission
      return fail_closed("no_enrolled_selfie")     unless submission.selfie.attached?

      liveness_bytes = download_bytes(liveness_blob)
      enrolled_bytes = download_bytes(submission.selfie)

      unless liveness_bytes && enrolled_bytes
        return fail_closed("download_failed")
      end

      response = rekognition.compare_faces(
        source_image: { bytes: liveness_bytes },
        target_image: { bytes: enrolled_bytes },
        similarity_threshold: 0
      )

      source_confidence = response.source_image_face&.confidence&.to_f
      if source_confidence && source_confidence < MIN_FACE_CONFIDENCE
        Rails.logger.warn(
          "[VoterFaceMatchService] Low source confidence for user ##{@user.id}: #{source_confidence}%"
        )
        return Result.new(
          matched: false,
          similarity: 0.0,
          status: "low_confidence",
          error_message: "Selfie face confidence too low (#{source_confidence.round(2)}%)"
        )
      end

      best = response.face_matches.max_by(&:similarity)
      similarity = best&.similarity&.to_f || 0.0
      matched = similarity >= SIMILARITY_THRESHOLD

      Rails.logger.info(
        "[VoterFaceMatchService] user=##{@user.id} similarity=#{similarity.round(2)}% matched=#{matched}"
      )

      Result.new(
        matched: matched,
        similarity: similarity.round(2),
        status: matched ? "match" : "no_match",
        error_message: nil
      )
    rescue Aws::Rekognition::Errors::ServiceError => e
      Rails.logger.error("[VoterFaceMatchService] AWS error for user ##{@user.id}: #{e.class} - #{e.message}")
      fail_closed("aws_error", error_message: e.message.truncate(200))
    rescue StandardError => e
      Rails.logger.error("[VoterFaceMatchService] Unexpected error for user ##{@user.id}: #{e.class} - #{e.message}")
      fail_closed("unexpected_error", error_message: e.message.truncate(200))
    end

    private

    def approved_submission
      @user.identity_submissions
           .where(status: :approved)
           .order(created_at: :desc)
           .first
    end

    def download_bytes(attachment_or_blob)
      blob = attachment_or_blob.respond_to?(:blob) ? attachment_or_blob.blob : attachment_or_blob
      blob.download
    rescue StandardError => e
      Rails.logger.warn("[VoterFaceMatchService] Direct blob download failed: #{e.class} - #{e.message}")
      begin
        url = blob.url(expires_in: 5.minutes)
        require "net/http"
        Net::HTTP.get(URI.parse(url))
      rescue StandardError => e2
        Rails.logger.error("[VoterFaceMatchService] URL fallback failed: #{e2.class} - #{e2.message}")
        nil
      end
    end

    def rekognition
      FaceMatchService.rekognition_client
    end

    def fail_closed(status, error_message: nil)
      Rails.logger.warn(
        "[VoterFaceMatchService] Failing closed for user ##{@user.id}: #{status}#{' — ' + error_message if error_message}"
      )
      Result.new(matched: false, similarity: 0.0, status: status, error_message: error_message)
    end
  end
end
