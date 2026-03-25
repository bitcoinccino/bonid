# app/jobs/generate_hotspot_report_job.rb
class GenerateHotspotReportJob < ApplicationJob
  queue_as :analytics

  def perform(period_days: 30)
    Rails.logger.info("Generating hotspot report for #{period_days} days")

    IncidentAnalyticsService.generate_hotspot_report(period: period_days.days)

    Rails.logger.info("Hotspot report generation complete")
  end
end
