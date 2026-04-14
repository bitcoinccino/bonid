# frozen_string_literal: true

# ReviewerActivity
# =================
# Audit trail for all reviewer actions in the identity verification pipeline.
# Tracks login, submission views, approvals, rejections, and warning overrides.
#
# Actions:
#   login              — reviewer signed in (IP tracked)
#   view_submission    — reviewer opened a pending submission (starts review timer)
#   approve            — reviewer approved a submission
#   reject             — reviewer rejected a submission (reason in metadata)
#   override_warning   — reviewer approved despite a system warning (e.g. face dedup flag)
#   logout             — reviewer signed out
#
class ReviewerActivity < ApplicationRecord
  belongs_to :user
  belongs_to :target, polymorphic: true, optional: true

  # ── Actions ──
  ACTIONS = %w[
    login
    logout
    view_submission
    approve
    reject
    override_warning
  ].freeze

  validates :action, presence: true, inclusion: { in: ACTIONS }

  # ── Scopes ──
  scope :logins,     -> { where(action: "login") }
  scope :reviews,    -> { where(action: %w[approve reject]) }
  scope :approvals,  -> { where(action: "approve") }
  scope :rejections, -> { where(action: "reject") }
  scope :overrides,  -> { where(action: "override_warning") }
  scope :views,      -> { where(action: "view_submission") }
  scope :recent,     -> { order(created_at: :desc) }
  scope :today,      -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :last_30_days, -> { where("created_at > ?", 30.days.ago) }

  scope :for_reviewer, ->(user_id) { where(user_id: user_id) }
  scope :for_submission, ->(submission) {
    where(target_type: "IdentitySubmission", target_id: submission.id)
  }

  # ── Logging helpers ──
  def self.log!(user:, action:, target: nil, ip_address: nil, metadata: {})
    create!(
      user:       user,
      action:     action,
      target:     target,
      ip_address: ip_address,
      metadata:   metadata
    )
  end

  # Calculate time spent reviewing (from view_submission to approve/reject)
  def self.review_duration_for(user_id, submission)
    view_event = for_reviewer(user_id)
      .for_submission(submission)
      .views
      .order(created_at: :desc)
      .first

    decision_event = for_reviewer(user_id)
      .for_submission(submission)
      .reviews
      .order(created_at: :desc)
      .first

    return nil unless view_event && decision_event

    (decision_event.created_at - view_event.created_at).to_i
  end
end
