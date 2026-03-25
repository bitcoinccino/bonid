# frozen_string_literal: true

# Runs OCR on uploaded CIN/Passport images after submission,
# cross-checks extracted text against citizen's form data,
# and stores results + mismatches in submission.metadata["ocr"].
#
class DocumentOcrJob < ApplicationJob
  queue_as :low

  def perform(identity_submission_id)
    submission = IdentitySubmission.find(identity_submission_id)
    user = submission.user

    # Pick the right image: CIN front or Passport
    blob = if submission.cin_front.attached?
             submission.cin_front.blob
           elsif submission.passport.attached?
             submission.passport.blob
           end

    return unless blob.present?

    Rails.logger.info("[DocumentOcrJob] Starting OCR for submission ##{submission.id} (#{submission.id_type})")

    # Run OCR
    service = DocumentOcrService.new(blob)
    result = service.extract

    # Cross-check against form data
    user_data = {
      last_name: user.last_name,
      first_name: user.first_name,
      dob: user.dob,
      sex: user.sex,
      document_number: submission.document_number
    }

    cross_check = DocumentOcrService.cross_check(result[:fields], user_data)

    mismatches = cross_check.select { |_, v| v[:match] == false }

    # Store in metadata
    ocr_data = {
      "extracted_fields" => result[:fields].transform_keys(&:to_s),
      "cross_check" => cross_check.transform_keys(&:to_s).transform_values { |v| v.transform_keys(&:to_s) },
      "mismatches" => mismatches.keys.map(&:to_s),
      "mismatch_count" => mismatches.size,
      "confidence" => result[:confidence],
      "processed_at" => Time.current.iso8601,
      "id_type" => submission.id_type
    }

    metadata = submission.metadata || {}
    metadata["ocr"] = ocr_data
    submission.update_column(:metadata, metadata)

    if mismatches.any?
      Rails.logger.warn("[DocumentOcrJob] #{mismatches.size} mismatch(es) for submission ##{submission.id}: #{mismatches.keys.join(', ')}")
    else
      Rails.logger.info("[DocumentOcrJob] All fields match for submission ##{submission.id}")
    end

  rescue DocumentOcrService::OcrError => e
    Rails.logger.error("[DocumentOcrJob] OCR failed for submission ##{submission.id}: #{e.message}")

    metadata = submission.metadata || {}
    metadata["ocr"] = { "error" => e.message, "processed_at" => Time.current.iso8601 }
    submission.update_column(:metadata, metadata)
  end
end
