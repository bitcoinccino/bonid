# app/models/incident_link.rb
class IncidentLink < ApplicationRecord
  belongs_to :incident_report
  belongs_to :linked_incident, class_name: "IncidentReport"
  belongs_to :created_by, polymorphic: true, optional: true

  validates :link_type, presence: true
  validates :incident_report_id, uniqueness: { scope: :linked_incident_id, message: "already linked to this incident" }
  validate :cannot_link_to_self

  LINK_TYPES = %w[
    related
    escalation
    follow_up
    duplicate
    same_suspect
    same_victim
    same_location
  ].freeze

  validates :link_type, inclusion: { in: LINK_TYPES }

  scope :by_type, ->(type) { where(link_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  # Create bidirectional link
  def self.create_bidirectional(report_a, report_b, link_type:, notes: nil, created_by: nil)
    transaction do
      create!(
        incident_report: report_a,
        linked_incident: report_b,
        link_type: link_type,
        notes: notes,
        created_by: created_by
      )
      create!(
        incident_report: report_b,
        linked_incident: report_a,
        link_type: link_type,
        notes: notes,
        created_by: created_by
      )
    end
  end

  def link_type_label
    link_type.titleize
  end

  def link_type_icon
    case link_type
    when "same_suspect" then "ri-user-follow-line"
    when "same_victim" then "ri-user-heart-line"
    when "same_location" then "ri-map-pin-line"
    when "escalation" then "ri-arrow-up-circle-line"
    when "follow_up" then "ri-arrow-right-circle-line"
    when "duplicate" then "ri-file-copy-line"
    else "ri-link"
    end
  end

  private

  def cannot_link_to_self
    if incident_report_id == linked_incident_id
      errors.add(:linked_incident, "cannot be the same as the incident report")
    end
  end
end
