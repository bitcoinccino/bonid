# frozen_string_literal: true

# app/models/visitor_access_grant.rb
class VisitorAccessGrant < ApplicationRecord
  belongs_to :visitor_submission

  EXPIRY = 10.minutes

  # ============================================================
  # CALLBACKS
  # ============================================================
  before_validation :generate_token, on: :create
  before_validation :set_expiry, on: :create

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # ============================================================
  # SCOPES
  # ============================================================
  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  # ============================================================
  # FACTORY (CONTROLLER ENTRY POINT)
  # ============================================================
  def self.issue!(visitor_submission:, ttl: EXPIRY)
    create!(
      visitor_submission: visitor_submission,
      expires_at: Time.current + ttl
    )
  end

  # ============================================================
  # STATE HELPERS
  # ============================================================
  def expired?
    expires_at.past?
  end

  def consumed?
    consumed_at.present?
  end

  def valid_for_use?
    !expired? && !consumed?
  end

  def consumable?
    valid_for_use?
  end

  # ============================================================
  # CONSUMPTION
  # ============================================================
  def consume!
    return if consumed?

    update!(consumed_at: Time.current)
  end

  def not_expired?
    !expired?
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(48)
  end

  def set_expiry
    self.expires_at ||= EXPIRY.from_now
  end
end
