# app/jobs/generate_officer_metrics_job.rb
class GenerateOfficerMetricsJob < ApplicationJob
  queue_as :analytics

  def perform(period_days: 30)
    Rails.logger.info("Generating officer metrics for #{period_days} days")

    period_end = Time.current
    period_start = period_days.days.ago

    IncidentAnalyticsService.generate_officer_metrics(
      period_start: period_start,
      period_end: period_end
    )

    Rails.logger.info("Officer metrics generation complete")
  end
end
