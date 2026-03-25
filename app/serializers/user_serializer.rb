# frozen_string_literal: true

class UserSerializer < ActiveModel::Serializer
  include Rails.application.routes.url_helpers

  attributes :id,
             :bonid,
             :verification_status,
             :verified_at,
             :expires_at,
             :first_name,
             :last_name,
             :dob,
             :sex,
             :nationality,
             :phone,
             :email,
             :address,
             :photo_url,
             :qr_verify_url,
             :verification_records

  # ============================
  # === BASIC BONID PROFILE ===
  # ============================

  def bonid
    object.bonid_profile[:bonid]
  end

  def verification_status
    object.bonid_profile[:verification_status]
  end

  def verified_at
    safe_time(object.bonid_profile[:verified_at])
  end

  def expires_at
    safe_time(object.bonid_profile[:expires_at])
  end

  def dob
    safe_time(object.dob)
  end

  def address
    object.formatted_address
  end

  def photo_url
    url_for(object.photo) if object.photo.attached?
  end

  def qr_verify_url
    "https://bonid.ht/verify/#{bonid}"
  end

  # =====================================
  # === NESTED VERIFICATION RECORDS ===
  # =====================================
  def verification_records
    records = object.verification_records.order(created_at: :desc)

    ActiveModel::Serializer::CollectionSerializer.new(
      records,
      serializer: ->(record, _) { resolve_record_serializer(record) }
    )
  end

  private

  # Dynamically resolve record-specific serializer
  def resolve_record_serializer(record)
    case record.record_type
    when "business"
      VerificationRecord::BusinessSerializer
    when "education"
      VerificationRecord::EducationSerializer
    when "health"
      VerificationRecord::HealthSerializer
    when "property"
      VerificationRecord::PropertySerializer
    else
      VerificationRecordSerializer # fallback default
    end
  end

  # === Safe formatter to prevent Date → String errors ===
  def safe_time(value)
    return nil if value.blank?
    return value.iso8601 if value.respond_to?(:iso8601)
    value.to_s
  end
end
