# app/serializers/citizen_summary_serializer.rb
class CitizenSummarySerializer < Blueprinter::Base
  fields :first_name, :last_name, :dob, :sex, :nationality, :address
end

# app/serializers/identity_submission_base_serializer.rb
#
# Non-namespaced base serializer for identity submissions.
# Mirrors Api::Partner::IdentitySubmissionBaseSerializer.
#
# Security:
#   • Uses UUID as the identifier — integer IDs are never exposed.
#   • Raw metadata is NOT serialized. Only safe, curated fields are exposed.
#
class IdentitySubmissionBaseSerializer < Blueprinter::Base
  identifier :uuid

  fields :bonid, :status, :submission_type, :verified_at, :expires_at,
         :document_issuer, :signature_hash, :hmac_signature

  # ── Biometrics Trust Block (Risk-Score API v1.1.0) ──────────────────

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

# app/serializers/identity_submission_partner_view_serializer.rb
class IdentitySubmissionPartnerViewSerializer < IdentitySubmissionBaseSerializer
  fields :qr_public_url, :verified_by, :partner
end

# app/serializers/verified_identity_serializer.rb
class VerifiedIdentitySerializer < Blueprinter::Base
  association :citizen, blueprint: CitizenSummarySerializer
  view :partner do
    association :verification, blueprint: IdentitySubmissionPartnerViewSerializer
  end
end

# app/serializers/partner_profile_serializer.rb
class PartnerProfileSerializer < Blueprinter::Base
  identifier :uuid
  fields :name, :sector, :email, :api_key_prefix, :sandbox_mode
  field :rate_limit do |partner|
    { limit: partner.rate_limit, remaining: partner.remaining_limit }
  end
end
