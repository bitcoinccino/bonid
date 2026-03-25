# app/controllers/admin/incident_analytics_controller.rb
module Admin
  class IncidentAnalyticsController < Admin::BaseController
    before_action :set_period

    def index
      @stats = IncidentAnalyticsService.dashboard_stats(period: @period)
      @trend_data = IncidentAnalyticsService.incident_trend(@period, interval: @interval)
      @comparison = IncidentAnalyticsService.period_comparison(
        current_period: @period,
        previous_period: @period * 2
      )
    end

    def hotspots
      @hotspots = CrimeHotspot
        .where("period_end >= ?", 30.days.ago)
        .includes(:commune)
        .order(severity_score: :desc)
        .limit(20)

      respond_to do |format|
        format.html
        format.json { render json: @hotspots }
      end
    end

    def officers
      @officer_metrics = OfficerMetric
        .where("period_end >= ?", 30.days.ago)
        .includes(:officer)
        .order(reports_submitted: :desc)
        .limit(20)
    end

    def crime_types
      @crime_stats = IncidentAnalyticsService.top_crime_types(@period, limit: 25)
      @categories = CrimeCategory.includes(:crime_types).where(active: true).order(:display_order)
    end

    def generate_hotspot_report
      IncidentAnalyticsService.generate_hotspot_report(period: @period)
      redirect_to admin_incident_analytics_hotspots_path, notice: "Hotspot report generated successfully"
    end

    def generate_officer_metrics
      IncidentAnalyticsService.generate_officer_metrics(
        period_start: @period.ago,
        period_end: Time.current
      )
      redirect_to admin_incident_analytics_officers_path, notice: "Officer metrics generated successfully"
    end

    private

    def set_period
      @period = case params[:period]
                when "7d" then 7.days
                when "30d" then 30.days
                when "90d" then 90.days
                when "1y" then 365.days
                else 30.days
                end

      @interval = case params[:interval]
                  when "hour" then :hour
                  when "day" then :day
                  when "week" then :week
                  when "month" then :month
                  else :day
                  end
    end
  end
end
