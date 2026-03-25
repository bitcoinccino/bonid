# app/jobs/daily_analytics_job.rb
# Scheduled daily to regenerate all analytics data
class DailyAnalyticsJob < ApplicationJob
  queue_as :analytics

  def perform
    Rails.logger.info("Starting daily analytics generation")

    # Generate hotspot reports for multiple periods
    [7, 30, 90].each do |days|
      GenerateHotspotReportJob.perform_later(period_days: days)
    end

    # Generate officer metrics for multiple periods
    [7, 30, 90].each do |days|
      GenerateOfficerMetricsJob.perform_later(period_days: days)
    end

    Rails.logger.info("Daily analytics jobs queued")
  end
end
