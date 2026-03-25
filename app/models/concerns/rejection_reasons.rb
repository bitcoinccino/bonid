# frozen_string_literal: true

#
module RejectionReasons
  extend ActiveSupport::Concern

  included do
    # === Enum Declaration (Rails 8 string-backed version) ===
    enum :rejection_reason, {
      blurry_documents: "blurry_documents",
      incorrect_id: "incorrect_id",
      expired_id: "expired_id",
      missing_selfie: "missing_selfie",
      mismatch_name: "mismatch_name",
      inconsistent_info: "inconsistent_info",
      invalid_proof_of_address: "invalid_proof_of_address",
      expired_proof_of_address: "expired_proof_of_address",
      duplicate_submission: "duplicate_submission",
      unverified_identity: "unverified_identity",
      suspected_tampering: "suspected_tampering",
      non_haitian_id: "non_haitian_id",
      incomplete_submission: "incomplete_submission",
      other: "other"
    }, prefix: true

    validates :rejection_reason,
      inclusion: { in: PartnerRejectionConstants::REJECTION_REASONS.keys.map(&:to_s) },
      allow_nil: true,
      on: :rejection
  end

  class_methods do
    # === Form options for dropdowns (with I18n support) ===
    def rejection_reasons_options
      rejection_reasons.map do |key, _|
        [
          I18n.t("rejection_reasons.#{key}", default: key.to_s.humanize),
          key
        ]
      end
    end
  end

  # === Instance Helpers ===
  def rejection_reason_label
    return "—" if rejection_reason.blank?
    I18n.t("rejection_reasons.#{rejection_reason}", default: rejection_reason.to_s.humanize)
  end

  # === Rejection Reason Mapping ===
  def user_friendly_rejection_reason(reason)
    return "" if reason.blank?

    case reason.to_s.strip
    when "inconsistent_info"
      "Some of the information you submitted does not match."
    when "Missing CIN or Passport document"
      "You need to upload either a CIN (both front and back) or a passport."
    when "CIN or Passport photo is blurry or unreadable"
      "Your ID photo is too blurry to be read clearly."
    when "CIN or Passport does not match selfie"
      "The ID document does not match your selfie."
    when "Selfie is missing"
      "A selfie is required for verification."
    when "Selfie is too blurry or unclear"
      "Your selfie is too blurry to verify your identity."
    when "Proof of Address is missing"
      "Please upload a proof of address (e.g., a Digicel bill)."
    when "Proof of Address is invalid (not a Digicel bill)"
      "Only Digicel bills are accepted as valid proof of address."
    when "Proof of Address is outdated"
      "Your proof of address document is too old."
    when "Information provided is inconsistent"
      "Some of the information you submitted does not match."
    when "Name mismatch between documents"
      "Your name is not consistent across your documents."
    when "Expired identification document", "expired_id"
      "Your ID is expired and can’t be used for verification."
    when "Low quality or incomplete document uploads", "blurry_documents"
      "Some uploaded documents are either incomplete or low quality."
    when "Multiple submissions with conflicting information", "duplicate_submission"
      "You submitted conflicting information across multiple requests."
    when "Identity could not be verified", "unverified_identity"
      "We couldn’t verify your identity with the submitted documents."
    when "Suspicious or altered documents detected", "suspected_tampering"
      "Some documents appear to be altered or suspicious."
    when "Document tampering suspected"
      "Your documents show signs of tampering."
    when "Duplicate identity submission detected"
      "You’ve already submitted an identity with matching data."
    when "Non-Haitian ID submitted", "non_haitian_id"
      "Only Haitian-issued identification is accepted."
    when "Incomplete submission", "incomplete_submission"
      "Some required documents or information are missing."
    when "Other (please specify below)", "other"
      "Your submission was rejected for another reason. Please review your documents."
    when "Bulk rejection by admin"
      "Your submission was rejected during a batch review and didn’t meet verification criteria."
    else
      reason.to_s.humanize
    end
  end
end
