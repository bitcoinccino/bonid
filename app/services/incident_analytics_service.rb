# app/services/incident_analytics_service.rb
# Aggregated analytics for incident reports
class IncidentAnalyticsService
  # === Dashboard Stats ===
  def self.dashboard_stats(period: 30.days)
    {
      total_incidents: total_incidents(period),
      by_status: incidents_by_status(period),
      by_crime_category: incidents_by_crime_category(period),
      by_severity: incidents_by_severity(period),
      trend: incident_trend(period),
      top_crime_types: top_crime_types(period, limit: 10),
      hotspot_communes: hotspot_communes(period, limit: 10),
      officer_stats: top_officers(period, limit: 10),
      review_stats: review_statistics(period)
    }
  end

  # === Time-Series Data ===
  def self.incident_trend(period, interval: :day)
    start_date = period.ago.beginning_of_day

    IncidentReport
      .where("created_at >= ?", start_date)
      .group_by_period(interval, :created_at)
      .count
  end

  def self.crime_trend_by_type(crime_type, period: 90.days, interval: :week)
    start_date = period.ago.beginning_of_day

    IncidentReport
      .where(crime_type: crime_type)
      .where("created_at >= ?", start_date)
      .group_by_period(interval, :created_at)
      .count
  end

  # === Aggregations ===
  def self.total_incidents(period)
    IncidentReport.where("created_at >= ?", period.ago).count
  end

  def self.incidents_by_status(period)
    IncidentReport
      .where("created_at >= ?", period.ago)
      .group(:status)
      .count
  end

  def self.incidents_by_crime_category(period)
    # Group by crime category (first word of crime_type for legacy data)
    IncidentReport
      .where("created_at >= ?", period.ago)
      .group(:crime_type)
      .count
      .transform_keys { |ct| categorize_crime(ct) }
      .each_with_object(Hash.new(0)) { |(k, v), h| h[k] += v }
  end

  def self.incidents_by_severity(period)
    # Would use crime_type_record.base_severity with new schema
    # For now, approximate from crime type
    IncidentReport
      .where("created_at >= ?", period.ago)
      .group(:crime_type)
      .count
      .transform_keys { |ct| crime_severity(ct) }
      .each_with_object(Hash.new(0)) { |(k, v), h| h[k] += v }
  end

  def self.top_crime_types(period, limit: 10)
    IncidentReport
      .where("created_at >= ?", period.ago)
      .group(:crime_type)
      .order("count_all DESC")
      .limit(limit)
      .count
  end

  def self.hotspot_communes(period, limit: 10)
    IncidentReport
      .joins(:address)
      .where("incident_reports.created_at >= ?", period.ago)
      .group("addresses.commune_id")
      .order("count_all DESC")
      .limit(limit)
      .count
      .transform_keys { |id| Commune.find_by(id: id)&.name || "Unknown" }
  end

  def self.top_officers(period, limit: 10)
    IncidentReport
      .where("created_at >= ?", period.ago)
      .group(:officer_id)
      .order("count_all DESC")
      .limit(limit)
      .count
      .map do |officer_id, count|
        officer = Officer.find_by(id: officer_id)
        {
          id: officer_id,
          name: officer&.full_name || "Unknown",
          unit: officer&.unit_name,
          count: count
        }
      end
  end

  def self.review_statistics(period)
    reviews = IncidentReport.where("created_at >= ?", period.ago)

    approved = reviews.where(status: :approved).count
    rejected = reviews.where(status: :rejected).count
    pending = reviews.where(status: [:submitted, :under_review]).count
    total = approved + rejected + pending

    {
      total_reviewed: approved + rejected,
      pending: pending,
      approval_rate: total > 0 ? (approved.to_f / total * 100).round(1) : 0,
      avg_review_time_hours: calculate_avg_review_time(period)
    }
  end

  # === Geographic Analysis ===
  def self.generate_hotspot_report(period: 30.days)
    communes = Commune.all

    communes.map do |commune|
      incidents = IncidentReport
        .joins(:address)
        .where(addresses: { commune_id: commune.id })
        .where("incident_reports.created_at >= ?", period.ago)

      breakdown = incidents.group(:crime_type).count
      severity_sum = breakdown.sum { |ct, count| crime_severity(ct) * count }

      CrimeHotspot.find_or_initialize_by(
        commune_id: commune.id,
        period_start: period.ago.to_date,
        period_end: Date.current
      ).tap do |hotspot|
        hotspot.incident_count = incidents.count
        hotspot.severity_score = severity_sum
        hotspot.breakdown = breakdown
        hotspot.save
      end
    end
  end

  # === Officer Metrics ===
  def self.generate_officer_metrics(period_start:, period_end:)
    Officer.find_each do |officer|
      reports = officer.incident_reports
                       .where(created_at: period_start..period_end)

      OfficerMetric.find_or_initialize_by(
        officer_id: officer.id,
        period_start: period_start.to_date,
        period_end: period_end.to_date
      ).tap do |metric|
        metric.reports_submitted = reports.count
        metric.reports_approved = reports.where(status: :approved).count
        metric.reports_rejected = reports.where(status: :rejected).count
        metric.approval_rate = metric.reports_submitted > 0 ?
          (metric.reports_approved.to_f / metric.reports_submitted * 100).round(1) : 0
        metric.bonid_scans = officer.qr_scans.where(created_at: period_start..period_end).count
        metric.crime_type_breakdown = reports.group(:crime_type).count
        metric.save
      end
    end
  end

  # === Comparison Analysis ===
  def self.period_comparison(current_period: 30.days, previous_period: 60.days)
    current_start = current_period.ago
    previous_start = previous_period.ago
    previous_end = current_period.ago

    current = IncidentReport.where("created_at >= ?", current_start)
    previous = IncidentReport.where(created_at: previous_start..previous_end)

    {
      current_count: current.count,
      previous_count: previous.count,
      change_percentage: calculate_change_percentage(current.count, previous.count),
      current_by_type: current.group(:crime_type).count,
      previous_by_type: previous.group(:crime_type).count
    }
  end

  private

  def self.categorize_crime(crime_type)
    return "Unknown" unless crime_type

    categories = IncidentReport::CRIME_TYPES
    categories.each do |category, types|
      return category.to_s.titleize if types.include?(crime_type)
    end
    "Other"
  end

  def self.crime_severity(crime_type)
    return 1 unless crime_type
    CrimeConstants::CRIME_SEVERITY[crime_type.downcase] || 2
  end

  def self.calculate_avg_review_time(period)
    reviewed = IncidentReport
      .where("created_at >= ?", period.ago)
      .where(status: [:approved, :rejected])
      .where.not(submitted_at: nil)

    return nil if reviewed.empty?

    total_hours = reviewed.sum do |r|
      ((r.updated_at - r.submitted_at) / 1.hour).round(1)
    end

    (total_hours / reviewed.count).round(1)
  end

  def self.calculate_change_percentage(current, previous)
    return 0 if previous == 0
    ((current - previous).to_f / previous * 100).round(1)
  end
end
