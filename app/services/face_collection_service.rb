# frozen_string_literal: true

# app/services/face_collection_service.rb
#
# Manages AWS Rekognition face collection for 1:N deduplication.
# Prevents the same person from creating multiple BonID accounts
# with different documents/names.
#
# Three operations:
#   1. search  — 1:N search before 1:1 match (fraud gate)
#   2. index   — store face on approval (build the collection)
#   3. remove  — delete face on revocation (cleanup)
#
# The collection links each indexed face to a user_id via ExternalImageId.
# On search, if a match is found for a DIFFERENT user_id → fraud.
# If the match belongs to the SAME user_id → legitimate reissue.
#
class FaceCollectionService
  require "aws-sdk-rekognition"

  COLLECTION_ID = "bonid-verified-faces"

  # 1:N threshold is higher than 1:1 (80%) to minimize false positives
  # across different lighting, angles, and submission sessions.
  SEARCH_THRESHOLD = 90.0

  # Maximum faces to return from a search
  MAX_FACES = 5

  class << self
    # ── Search: Is this face already in the system? ─────────────────────
    #
    # Returns:
    #   { duplicate: false }                          — face not found, safe to proceed
    #   { duplicate: false, same_user: true }          — face found but belongs to same user (reissue)
    #   { duplicate: true,  matched_user_id: 123, similarity: 95.2 } — fraud
    #   { error: "message" }                          — AWS error, don't block
    #
    def search(selfie_bytes, current_user_id)
      return { duplicate: false } unless collection_exists?

      response = rekognition_client.search_faces_by_image(
        collection_id: COLLECTION_ID,
        image: { bytes: selfie_bytes },
        face_match_threshold: SEARCH_THRESHOLD,
        max_faces: MAX_FACES
      )

      return { duplicate: false } if response.face_matches.empty?

      # Check each match — look for a different user
      response.face_matches.each do |match|
        matched_user_id = match.face.external_image_id.to_i
        similarity = match.similarity.round(2)

        if matched_user_id != current_user_id
          Rails.logger.warn "[FaceCollectionService] DUPLICATE DETECTED: " \
            "user_id=#{current_user_id} matches existing user_id=#{matched_user_id} " \
            "(similarity: #{similarity}%, face_id: #{match.face.face_id})"

          return {
            duplicate: true,
            matched_user_id: matched_user_id,
            matched_face_id: match.face.face_id,
            similarity: similarity
          }
        end
      end

      # All matches belong to the same user — legitimate reissue
      Rails.logger.info "[FaceCollectionService] Face found for same user_id=#{current_user_id} (reissue). Allowing."
      { duplicate: false, same_user: true }

    rescue Aws::Rekognition::Errors::InvalidParameterException => e
      if e.message.downcase.include?("no face")
        Rails.logger.warn "[FaceCollectionService] No face detected in selfie for search: #{e.message}"
        { duplicate: false, no_face: true }
      else
        Rails.logger.error "[FaceCollectionService] Search error: #{e.class} - #{e.message}"
        { error: e.message }
      end
    rescue Aws::Rekognition::Errors::ServiceError => e
      Rails.logger.error "[FaceCollectionService] Search error: #{e.class} - #{e.message}"
      { error: e.message }
    end

    # ── Index: Store a face in the collection on approval ───────────────
    #
    # ExternalImageId stores the user_id so we can identify who the face
    # belongs to during search. Returns the Rekognition face_id or nil.
    #
    def index(selfie_bytes, user_id)
      ensure_collection!

      response = rekognition_client.index_faces(
        collection_id: COLLECTION_ID,
        image: { bytes: selfie_bytes },
        external_image_id: user_id.to_s,
        max_faces: 1,
        detection_attributes: ["DEFAULT"],
        quality_filter: "AUTO"
      )

      if response.face_records.any?
        face_id = response.face_records.first.face.face_id
        Rails.logger.info "[FaceCollectionService] Indexed face for user_id=#{user_id}: face_id=#{face_id}"
        face_id
      else
        Rails.logger.warn "[FaceCollectionService] No face indexed for user_id=#{user_id} (quality filter may have rejected it)"
        nil
      end

    rescue Aws::Rekognition::Errors::ServiceError => e
      Rails.logger.error "[FaceCollectionService] Index error for user_id=#{user_id}: #{e.class} - #{e.message}"
      nil
    end

    # ── Remove: Delete a face from the collection on revocation ─────────
    #
    def remove(face_id)
      return unless face_id.present?

      rekognition_client.delete_faces(
        collection_id: COLLECTION_ID,
        face_ids: [face_id]
      )

      Rails.logger.info "[FaceCollectionService] Removed face_id=#{face_id} from collection"
      true

    rescue Aws::Rekognition::Errors::ServiceError => e
      Rails.logger.error "[FaceCollectionService] Remove error for face_id=#{face_id}: #{e.class} - #{e.message}"
      false
    end

    # ── Collection management ───────────────────────────────────────────

    def ensure_collection!
      return if collection_exists?

      rekognition_client.create_collection(collection_id: COLLECTION_ID)
      Rails.logger.info "[FaceCollectionService] Created collection: #{COLLECTION_ID}"
    rescue Aws::Rekognition::Errors::ResourceAlreadyExistsException
      # Race condition — another process created it
    end

    def collection_exists?
      rekognition_client.describe_collection(collection_id: COLLECTION_ID)
      true
    rescue Aws::Rekognition::Errors::ResourceNotFoundException
      false
    end

    def collection_stats
      response = rekognition_client.describe_collection(collection_id: COLLECTION_ID)
      {
        face_count: response.face_count,
        created_at: response.creation_timestamp,
        model_version: response.face_model_version
      }
    rescue Aws::Rekognition::Errors::ResourceNotFoundException
      { face_count: 0, exists: false }
    end

    private

    def rekognition_client
      FaceMatchService.rekognition_client
    end
  end
end
