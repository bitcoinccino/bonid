# frozen_string_literal: true

# DailyReviewSummaryJob
#
# Runs daily at 8am to send supervisors a summary of pending reviews.
# Helps supervisors plan their day and prioritize high-severity cases.
#
# Scheduled via config/recurring.yml
#
class DailyReviewSummaryJob < ApplicationJob
  queue_as :default

  def perform
    # Group pending reviews by reviewer
    pending_by_reviewer = IncidentReview.pending
                                        .includes(:reviewer, incident_report: :officer)
                                        .group_by(&:reviewer)

    pending_by_reviewer.each do |reviewer, reviews|
      next unless reviewer&.email.present?

      # Build summary data
      summary = build_summary(reviews)

      # Send daily summary email
      Officers::OfficerMailer.with(
        reviewer: reviewer,
        summary: summary
      ).daily_review_summary.deliver_later
    end

    Rails.logger.info "[DailyReviewSummary] Sent summaries to #{pending_by_reviewer.keys.compact.count} reviewers"
  end

  private

  def build_summary(reviews)
    {
      total_pending: reviews.count,
      overdue: reviews.count { |r| r.overdue? },
      due_today: reviews.count { |r| r.deadline_at&.today? },
      critical_priority: reviews.count { |r| r.priority >= 3 },
      urgent_priority: reviews.count { |r| r.priority == 2 },
      reviews: reviews.sort_by { |r| [r.overdue? ? 0 : 1, -(r.priority || 0), r.deadline_at || Time.current] }
                      .first(10) # Top 10 most urgent
    }
  end
end
