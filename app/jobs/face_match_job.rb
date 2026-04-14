# frozen_string_literal: true

require "aws-sdk-rekognition"

# app/jobs/face_match_job.rb
#
# Runs face matching asynchronously after a citizen submits their identity documents.
# In development, queue_adapter is :inline so this runs synchronously.
# In production, it uses solid_queue.
#
# SECURITY: Auto-rejects submissions when face match clearly fails:
#   - "no_match"         → selfie doesn't match ID face (e.g., different person)
#   - "no_face_detected" → no human face found on ID (e.g., animal photo, scenery)
# This prevents junk/fraudulent submissions from sitting as "pending" for admin review.
#
class FaceMatchJob < ApplicationJob
  queue_as :default

  # Retry once on transient AWS errors, then give up gracefully
  retry_on Aws::Rekognition::Errors::ServiceError, wait: 30.seconds, attempts: 2
  discard_on ActiveJob::DeserializationError

  def perform(submission_id)
    submission = IdentitySubmission.find_by(id: submission_id)

    unless submission
      Rails.logger.warn "[FaceMatchJob] Submission ##{submission_id} not found, skipping."
      return
    end

    # Only run face match for pending submissions
    unless submission.status_pending?
      Rails.logger.info "[FaceMatchJob] Submission ##{submission_id} is #{submission.status}, skipping face match."
      return
    end

    # Skip if face match was already performed successfully (allow retry on errors)
    existing_status = submission.metadata&.dig("face_match", "status")
    if existing_status.present? && existing_status != "error"
      Rails.logger.info "[FaceMatchJob] Submission ##{submission_id} already has face match result (#{existing_status}), skipping."
      return
    end

    # Skip if no selfie or ID document attached
    unless submission.selfie.attached? && (submission.cin_front.attached? || submission.passport.attached?)
      Rails.logger.info "[FaceMatchJob] Submission ##{submission_id} missing selfie or ID document, skipping."
      return
    end

    # Skip if AWS Rekognition credentials not configured
    unless Rails.application.credentials.dig(:aws, :rekognition, :access_key_id).present?
      Rails.logger.info "[FaceMatchJob] AWS Rekognition not configured, skipping face match."
      return
    end

    # ── LAYER 1: 1:N face deduplication (before 1:1 match) ──
    # Search the Rekognition collection for this face across ALL verified users.
    # If the face belongs to a different user → auto-reject as duplicate.
    # If it belongs to the same user → legitimate reissue, continue.
    selfie_bytes = download_selfie_bytes(submission)
    if selfie_bytes
      dedup_result = FaceCollectionService.search(selfie_bytes, submission.user_id)
      if dedup_result[:duplicate]
        auto_reject_duplicate!(submission, dedup_result)
        return
      end

      # Store dedup result in metadata for admin visibility
      store_dedup_result!(submission, dedup_result)
    end

    # ── LAYER 2: 1:1 face match (selfie vs ID document) ──
    result = FaceMatchService.call(submission)

    # Reload to pick up metadata changes written by FaceMatchService
    submission.reload

    # ── SECURITY GATE: Auto-reject on clear face match failures ──
    # This prevents fraudulent/junk submissions (animal photos, wrong person, etc.)
    # from sitting as "pending" and wasting admin review time.
    enforce_face_match!(submission, result)
  rescue StandardError => e
    Rails.logger.error "[FaceMatchJob] Error processing submission ##{submission_id}: #{e.class} - #{e.message}"
    # Store error in metadata so admin can see something failed
    # Do NOT auto-reject on errors — could be transient AWS issues
    if submission
      submission.update_column(:metadata,
        (submission.metadata || {}).merge(
          "face_match" => {
            "status" => "error",
            "error_message" => "Job failed: #{e.message.truncate(200)}",
            "matched_at" => Time.current.iso8601
          }
        )
      )
    end
  end

  private

  def enforce_face_match!(submission, result)
    return unless submission.status_pending?

    face_status = result[:status] || submission.metadata&.dig("face_match", "status")

    case face_status
    when "match"
      # Face matched — leave as pending for admin to review documents
      Rails.logger.info "[FaceMatchJob] Submission ##{submission.id}: Face matched (#{result[:similarity]}%), awaiting admin review."

    when "no_match"
      # Selfie doesn't match ID face — auto-reject
      similarity = result[:similarity] || 0
      auto_reject!(
        submission,
        reason: "unverified_identity",
        note: "Auto-rejected: Selfie does not match the face on the ID document (similarity: #{similarity}%, threshold: #{FaceMatchService::SIMILARITY_THRESHOLD}%)."
      )

    when "no_face_detected"
      # No human face found on ID document (animal photo, blank, scenery, etc.) — auto-reject
      auto_reject!(
        submission,
        reason: "unverified_identity",
        note: "Auto-rejected: No human face detected on the uploaded ID document. The document may contain a non-human image or be illegible."
      )

    when "error"
      # Service error — do NOT auto-reject, leave for admin
      Rails.logger.warn "[FaceMatchJob] Submission ##{submission.id}: Face match returned error, leaving as pending for admin review."

    else
      Rails.logger.warn "[FaceMatchJob] Submission ##{submission.id}: Unknown face match status '#{face_status}', leaving as pending."
    end
  end

  def download_selfie_bytes(submission)
    return nil unless submission.selfie.attached?

    blob = submission.selfie.blob
    blob.download
  rescue StandardError => e
    Rails.logger.warn "[FaceMatchJob] Failed to download selfie for 1:N search: #{e.message}"
    nil
  end

  def auto_reject_duplicate!(submission, dedup_result)
    matched_user_id = dedup_result[:matched_user_id]
    similarity = dedup_result[:similarity]

    Rails.logger.warn "[FaceMatchJob] DUPLICATE FACE — Auto-rejecting submission ##{submission.id}: " \
      "matches user_id=#{matched_user_id} (#{similarity}% similarity)"

    current_metadata = submission.metadata || {}
    current_metadata["face_dedup"] = {
      "status" => "duplicate",
      "matched_user_id" => matched_user_id,
      "matched_face_id" => dedup_result[:matched_face_id],
      "similarity" => similarity,
      "checked_at" => Time.current.iso8601
    }
    current_metadata["auto_rejection"] = {
      "rejected_by" => "system:face_dedup",
      "reason" => "duplicate_identity",
      "note" => "Auto-rejected: This face is already registered under a different BonID account " \
                "(user_id: #{matched_user_id}, similarity: #{similarity}%). " \
                "A person can only have one BonID.",
      "rejected_at" => Time.current.iso8601
    }

    submission.update!(
      status: :rejected,
      rejection_reason: "duplicate_identity",
      metadata: current_metadata
    )

    Citizens::IdentitySubmissionMailer.rejected_email(submission).deliver_later

    # Notify admin team of the fraud attempt
    Admin::AdminMailer.fraud_alert(submission: submission).deliver_later
    Rails.cache.delete("admin/fraud_alerts_count")
  rescue StandardError => e
    Rails.logger.error "[FaceMatchJob] Failed to auto-reject duplicate submission ##{submission.id}: #{e.class} - #{e.message}"
  end

  def store_dedup_result!(submission, dedup_result)
    current_metadata = submission.metadata || {}
    current_metadata["face_dedup"] = {
      "status" => dedup_result[:same_user] ? "same_user" : "clear",
      "checked_at" => Time.current.iso8601
    }
    submission.update_column(:metadata, current_metadata)
  end

  def auto_reject!(submission, reason:, note:)
    Rails.logger.warn "[FaceMatchJob] AUTO-REJECTING Submission ##{submission.id}: #{note}"

    # Store auto-rejection audit trail in metadata
    current_metadata = submission.metadata || {}
    current_metadata["auto_rejection"] = {
      "rejected_by" => "system:face_match",
      "reason" => reason,
      "note" => note,
      "rejected_at" => Time.current.iso8601
    }

    submission.update!(
      status: :rejected,
      rejection_reason: reason,
      metadata: current_metadata
    )

    # Notify the citizen so they can resubmit with correct documents
    Citizens::IdentitySubmissionMailer.rejected_email(submission).deliver_later
  rescue StandardError => e
    Rails.logger.error "[FaceMatchJob] Failed to auto-reject submission ##{submission.id}: #{e.class} - #{e.message}"
  end
end
