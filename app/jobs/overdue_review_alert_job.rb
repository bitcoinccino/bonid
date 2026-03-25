# app/jobs/overdue_review_alert_job.rb
class OverdueReviewAlertJob < ApplicationJob
  queue_as :default

  def perform
    # Find all overdue pending reviews
    IncidentReview.overdue.pending.find_each do |review|
      # Send alert to reviewer
      send_overdue_alert(review)

      # Auto-escalate if more than 72 hours overdue (24 hours past deadline)
      if review.deadline_at < 24.hours.ago
        escalate_review(review)
      end
    end

    # Log job completion
    Rails.logger.info "[OverdueReviewAlertJob] Processed #{IncidentReview.overdue.pending.count} overdue reviews"
  end

  private

  def send_overdue_alert(review)
    Officers::OfficerMailer.with(
      review: review,
      reviewer: review.reviewer
    ).overdue_review_alert.deliver_later
  rescue => e
    Rails.logger.error "[OverdueReviewAlertJob] Failed to send alert for review #{review.id}: #{e.message}"
  end

  def escalate_review(review)
    review.update!(decision: :escalated)

    # Notify higher authority about escalation
    Rails.logger.warn "[OverdueReviewAlertJob] Review #{review.id} auto-escalated due to being 24+ hours overdue"

    # Could also send escalation notification here
    # HigherAuthorityMailer.escalation_notice(review).deliver_later
  rescue => e
    Rails.logger.error "[OverdueReviewAlertJob] Failed to escalate review #{review.id}: #{e.message}"
  end
end
