# app/models/incident_review.rb
class IncidentReview < ApplicationRecord
  belongs_to :incident_report
  belongs_to :reviewer, class_name: "AdminUser"
  belongs_to :assigned_by, class_name: "AdminUser", optional: true
  has_many :review_comments, dependent: :destroy

  enum :decision, {
    pending: 0,
    approved: 1,
    rejected: 2,
    escalated: 3,
    info_requested: 4
  }, prefix: true

  validates :incident_report_id, presence: true
  validates :reviewer_id, presence: true

  scope :pending, -> { where(decision: :pending) }
  scope :completed, -> { where.not(decision: :pending) }
  scope :overdue, -> { pending.where("deadline_at < ?", Time.current) }
  scope :high_priority, -> { where("priority >= ?", 2) }
  scope :by_reviewer, ->(reviewer_id) { where(reviewer_id: reviewer_id) }
  scope :recent, -> { order(created_at: :desc) }

  before_save :set_completed_at, if: :decision_changed?

  # Assign review to a reviewer
  def self.assign(incident_report, reviewer:, assigned_by: nil, priority: 0, deadline: nil)
    create!(
      incident_report: incident_report,
      reviewer: reviewer,
      assigned_by: assigned_by,
      priority: priority,
      deadline_at: deadline || 48.hours.from_now,
      assigned_at: Time.current
    )
  end

  def complete!(decision:, summary: nil)
    update!(
      decision: decision,
      summary: summary,
      completed_at: Time.current
    )
  end

  def overdue?
    decision_pending? && deadline_at.present? && deadline_at < Time.current
  end

  def time_to_deadline
    return nil unless deadline_at.present?
    deadline_at - Time.current
  end

  def review_duration
    return nil unless completed_at.present?
    completed_at - created_at
  end

  def priority_label
    case priority
    when 0 then "Normal"
    when 1 then "High"
    when 2 then "Urgent"
    when 3 then "Critical"
    else "Normal"
    end
  end

  def priority_color
    case priority
    when 0 then "secondary"
    when 1 then "warning"
    when 2 then "danger"
    when 3 then "dark"
    else "secondary"
    end
  end

  private

  def set_completed_at
    self.completed_at = Time.current unless decision_pending?
  end
end
