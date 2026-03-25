# app/models/suspect_alert.rb
class SuspectAlert < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :created_by, polymorphic: true, optional: true
  belongs_to :source_incident, class_name: "IncidentReport", optional: true

  validates :alert_type, presence: true
  validate :must_have_identifier

  ALERT_TYPES = %w[
    wanted
    armed_dangerous
    missing
    person_of_interest
    escaped_custody
    suspected_gang_member
  ].freeze

  validates :alert_type, inclusion: { in: ALERT_TYPES }

  scope :active, -> { where(active: true).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :high_priority, -> { where("priority >= ?", 2) }
  scope :by_type, ->(type) { where(alert_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  # Check if a BonID has any active alerts
  def self.check_bonid(bonid)
    active.where(bonid: bonid).to_a
  end

  # Check if a user has any active alerts
  def self.check_user(user)
    active.where(user_id: user.id).or(active.where(bonid: user.bonid)).to_a
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def deactivate!
    update!(active: false)
  end

  def extend_expiry!(days: 30)
    update!(expires_at: days.days.from_now)
  end

  def alert_type_label
    alert_type.titleize
  end

  def alert_type_icon
    case alert_type
    when "wanted" then "ri-user-search-line"
    when "armed_dangerous" then "ri-sword-line"
    when "missing" then "ri-user-unfollow-line"
    when "person_of_interest" then "ri-eye-line"
    when "escaped_custody" then "ri-door-open-line"
    when "suspected_gang_member" then "ri-group-line"
    else "ri-alert-line"
    end
  end

  def priority_label
    case priority
    when 0 then "Low"
    when 1 then "Medium"
    when 2 then "High"
    when 3 then "Critical"
    else "Low"
    end
  end

  def priority_color
    case priority
    when 0 then "secondary"
    when 1 then "info"
    when 2 then "warning"
    when 3 then "danger"
    else "secondary"
    end
  end

  def display_name
    return user.full_name if user.present?
    name.presence || "Unknown"
  end

  private

  def must_have_identifier
    if user_id.blank? && bonid.blank? && name.blank?
      errors.add(:base, "Must have either a user, BonID, or name")
    end
  end
end
