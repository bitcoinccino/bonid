# frozen_string_literal: true

class ApiAccessLog < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================
  belongs_to :partner
  belongs_to :user, optional: true

  # ============================================================
  # Validations
  # ============================================================
  validates :partner_id, presence: true
  validates :endpoint, presence: true
  validates :ip_address, presence: true
  validates :success, inclusion: { in: [ true, false ] }

  # ============================================================
  # Callbacks
  # ============================================================
  before_save :stringify_metadata_dates

  # ============================================================
  # Scopes
  # ============================================================
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }

  # ============================================================
  # JSONB Safety — automatically convert all Date/Time values
  # ============================================================
  def stringify_metadata_dates
    return if metadata.blank?
    self.metadata = deep_stringify_dates(metadata)
  end

  private

  def deep_stringify_dates(obj)
    case obj
    when Hash
      obj.transform_values { |v| deep_stringify_dates(v) }
    when Array
      obj.map { |v| deep_stringify_dates(v) }
    when Time, DateTime, Date, ActiveSupport::TimeWithZone
      obj.iso8601
    else
      obj
    end
  end

  # ============================================================
  # Helper: Log a safe entry programmatically
  # ============================================================
  def self.log(partner:, user: nil, endpoint:, ip:, success:, status: nil, message: nil, metadata: {}, duration_ms: nil)
    create!(
      partner: partner,
      user: user,
      endpoint: endpoint,
      ip_address: ip,
      success: success,
      status: status,
      response_message: message,
      duration_ms: duration_ms,
      metadata: metadata.merge(
        logged_at: Time.current.iso8601,
        env: Rails.env
      )
    )
  rescue => e
    Rails.logger.error("[ApiAccessLog::Error] #{e.class}: #{e.message}")
  end
end
