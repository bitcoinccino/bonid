# app/models/review_comment.rb
class ReviewComment < ApplicationRecord
  belongs_to :incident_review
  belongs_to :admin_user
  belongs_to :person_involvement, optional: true

  validates :content, presence: true

  COMMENT_TYPES = %w[
    info_request
    correction
    note
    approval_reason
    rejection_reason
    escalation_reason
  ].freeze

  validates :comment_type, inclusion: { in: COMMENT_TYPES }, allow_nil: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(comment_type: type) }

  def comment_type_label
    comment_type&.titleize || "Comment"
  end

  def comment_type_icon
    case comment_type
    when "info_request" then "ri-question-line"
    when "correction" then "ri-edit-line"
    when "approval_reason" then "ri-check-line"
    when "rejection_reason" then "ri-close-line"
    when "escalation_reason" then "ri-arrow-up-line"
    else "ri-chat-1-line"
    end
  end
end
