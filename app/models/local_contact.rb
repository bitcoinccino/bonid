# frozen_string_literal: true

class LocalContact < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================
  belongs_to :visitor_submission, optional: true
  belongs_to :user, optional: true

  # ============================================================
  # Constants
  # ============================================================
  RELATIONSHIP_TYPES = %w[
    family
    friend
    hotel
    host
    employer
    organization
    other
  ].freeze

  # ============================================================
  # Validations
  # ============================================================
  validates :relationship,
            inclusion: { in: RELATIONSHIP_TYPES },
            allow_blank: true

  validates :name, presence: true, unless: :bonid_present?

  # ============================================================
  # Callbacks
  # ============================================================
  before_validation :normalize_phone
  before_update     :prevent_edit_if_verified

  # ============================================================
  # Phone helpers
  # ============================================================
  def full_phone_number
    return nil if phone.blank?

    "#{phone_country_code}#{phone}"
  end

  # ============================================================
  # Helpers
  # ============================================================
  def bonid_present?
    bonid.present?
  end

  private

  # ============================================================
  # Normalize phone safely (NO SMS sent here)
  # ============================================================
  def normalize_phone
    return if phone.blank?

    # Remove spaces, dashes, parentheses — keep digits only
    self.phone = phone.gsub(/[^\d]/, "")
  end

  # ============================================================
  # Security: Lock verified contacts
  # ============================================================
  def prevent_edit_if_verified
    return unless verified?
    return if new_record? # allow first save

    if will_save_change_to_name? ||
       will_save_change_to_phone? ||
       will_save_change_to_email? ||
       will_save_change_to_phone_country_code?

      errors.add(:base, "Verified contact cannot be modified")
      throw :abort
    end
  end
end
