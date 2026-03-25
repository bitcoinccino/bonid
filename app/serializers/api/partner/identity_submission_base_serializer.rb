# app/serializers/api/partner/identity_submission_base_serializer.rb
#
# Base Blueprinter serializer for identity submissions exposed to partners.
#
# Security:
#   • Uses UUID as the identifier — integer IDs are never exposed.
#   • Raw metadata is NOT serialized. Only safe, curated fields are exposed.
#   • Internal AWS session IDs, blob IDs, and submission IDs are excluded.
#
# Biometrics (Risk-Score API v1.1.0):
#   Exposes raw confidence scores so partner risk engines can apply their
#   own thresholds (e.g., banks require liveness > 90, NGOs accept > 70).
#
class Api::Partner::IdentitySubmissionBaseSerializer < Blueprinter::Base
  identifier :uuid

  fields :bonid,
         :status,
         :submission_type,
         :verified_at,
         :expires_at,
         :document_issuer,
         :signature_hash,
         :hmac_signature

  # ── Biometrics Trust Block ──────────────────────────────────────────
  # Exposes liveness + face-match confidence so partners can make
  # risk-based decisions (bank $10k transfer vs NGO aid distribution).

  field :liveness_confidence do |submission|
    submission.metadata&.dig("liveness", "confidence")&.to_f
  end

  field :face_match_similarity do |submission|
    submission.metadata&.dig("face_match", "similarity")&.to_f
  end

  field :face_match_threshold do |submission|
    submission.metadata&.dig("face_match", "threshold")&.to_f || 80.0
  end

  field :audit_status do |submission|
    liveness   = submission.metadata&.dig("liveness")
    face_match = submission.metadata&.dig("face_match")

    if liveness.blank? && face_match.blank?
      "not_performed"
    elsif liveness&.dig("passed") == true && face_match&.dig("status") == "match"
      "passed"
    else
      "failed"
    end
  end

  field :challenge_type do |_submission|
    "FaceMovementAndLightChallenge"
  end

  field :verified_with_review do |submission|
    liveness = submission.metadata&.dig("liveness")
    liveness&.dig("needs_review") == true && liveness&.dig("passed") == true
  end

  field :biometrics_reused do |submission|
    submission.metadata&.dig("liveness", "reused_from_submission_uuid").present? ||
      submission.metadata&.dig("liveness", "reused_from_submission_id").present?
  end

  field :liveness_checked_at do |submission|
    submission.metadata&.dig("liveness", "checked_at")
  end

  field :face_matched_at do |submission|
    submission.metadata&.dig("face_match", "matched_at")
  end
end
