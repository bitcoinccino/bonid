# frozen_string_literal: true

class VisitorScanEvent < ApplicationRecord
  belongs_to :visitor_submission, optional: true

  INPUT_METHODS = %w[qr_payload manual].freeze

  validates :bon_touris_id, presence: true
  validates :input_method, inclusion: { in: INPUT_METHODS }
  validates :status, presence: true
  validates :occurred_at, presence: true

  after_create_commit :notify_visitor_if_needed!

  # Throttle so we don't spam the visitor if a verifier refreshes / retries.
  THROTTLE_WINDOW = 3.minutes

  def notify_visitor_if_needed!
    return unless visitor_submission
    return unless visitor_submission.email.present?
    return unless visitor_submission.email_verified?
    return if notified_at.present?

    recent_notified = self.class.where(visitor_submission_id: visitor_submission_id)
                                .where("notified_at > ?", THROTTLE_WINDOW.ago)
                                .exists?
    return if recent_notified

    update_column(:notified_at, Time.current)

    VisitorMailer.with(event: self).scan_alert.deliver_later
  rescue => e
    Rails.logger.error("[VisitorScanEvent] notify failed ##{id}: #{e.class} #{e.message}")
  end

  # Nice display helpers for emails
  def occurred_at_local
    occurred_at.in_time_zone("America/New_York") # adjust if needed
  end

  def device_summary
    if defined?(Browser)
      b = Browser.new(user_agent.to_s, accept_language: accept_language.to_s)
      parts = []
      parts << (b.device.name.presence || "Device")
      parts << (b.platform.name.presence || "OS")
      parts << (b.name.presence || "Browser")
      parts.join(" · ")
    else
      user_agent.to_s
    end
  end

  def location_summary
    [ city, region, country ].compact_blank.join(", ").presence
  end
end
