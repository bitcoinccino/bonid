class CitizenSession < ApplicationRecord
  belongs_to :user
  belongs_to :citizen_profile, optional: true
  validates :login_source, :ip_address, :device_fingerprint, presence: true, unless: -> { Rails.env.development? || Rails.env.test? }

  scope :recent, -> { order(created_at: :desc) }

  # Rough device inference from user agent. Intentionally simple — the goal is a
  # friendly "mobile / tablet / desktop" label for the citizen, not analytics.
  def device_type
    ua = user_agent.to_s
    return "mobile" if ua.match?(/Mobi|Android|iPhone/i) && ua !~ /iPad|Tablet/i
    return "tablet" if ua.match?(/iPad|Tablet/i)
    "desktop"
  end

  # Was this the first time this citizen logged in from this IP?
  # Inspected per-row — cheap because it hits the already-indexed user_id column.
  # Callers doing this in a loop should batch via .preload_new_device_flags instead.
  def new_device?
    return false unless user_id.present? && ip_address.present?
    !CitizenSession
      .where(user_id: user_id, ip_address: ip_address)
      .where("created_at < ?", created_at)
      .exists?
  end
end
