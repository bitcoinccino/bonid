# frozen_string_literal: true

module Officers
  class AnalyticsController < Officers::BaseController
    before_action :authenticate_officer!
    before_action :set_date_range
    before_action :set_scope

    def index
      @stats = calculate_overview_stats
      @crime_breakdown = calculate_crime_breakdown
      @recent_trend = calculate_recent_trend
      @performance = calculate_performance_metrics
      @top_locations = calculate_hot_zone_data.sort_by { |z| -z[:count] }.first(5)
    end

    def crime_breakdown
      @crime_data = calculate_detailed_crime_breakdown
      @severity_breakdown = calculate_severity_breakdown
    end

    def hot_zones
      @zone_data = calculate_hot_zone_data
      @department_breakdown = calculate_department_breakdown
    end

    def demographics
      @gender_data = calculate_gender_data
      @role_breakdown = calculate_role_breakdown
    end

    def geographic
      @department_data = calculate_geographic_by_department
      @commune_data = calculate_geographic_by_commune
      @period_comparison = calculate_period_comparison
    end

    def temporal
      @daily_pattern = calculate_daily_pattern
      @monthly_trend = calculate_monthly_trend
      @hourly_distribution = calculate_hourly_distribution
    end

    def seasonal
      @seasonal_data = calculate_seasonal_breakdown
      @seasonal_crime_types = calculate_seasonal_crime_types
      @seasonal_yoy = calculate_seasonal_yoy
      @seasonal_severity = calculate_seasonal_severity
    end

    def performance
      @my_stats = calculate_my_performance
      @comparison = calculate_comparison_to_average
      @resolution_rates = calculate_resolution_rates
    end

    def chart_data
      data = case params[:chart_type]
             when "crime_pie" then crime_pie_data
             when "timeline" then timeline_data
             else { error: "Unknown chart type" }
             end
      render json: data
    end

    def crime_location
      @reports = @scoped_reports.joins(:address).where.not(addresses: { latitude: nil, longitude: nil })
      @crime_locations = @reports.includes(:address).map do |r|
        {
          lat: r.address.latitude,
          lng: r.address.longitude,
          crime_type: r.crime_type,
          occurred_at: r.occurred_at&.strftime("%b %d, %Y"),
          severity: r.crime_severity_level
        }
      end
      @location_stats = {
        total: @reports.count,
        by_type: @reports.group(:crime_type).count.sort_by { |_, v| -v }.first(5).to_h
      }
    end

    def incident_reports_bonid
      # Reports involving citizens (BonID holders)
      base_reports = @scoped_reports.joins(:person_involvements)
                                    .where(person_involvements: { visitor_submission_id: nil })
                                    .where.not(person_involvements: { user_id: nil })
                                    .distinct

      @total_count = base_reports.count
      @by_crime_type = base_reports.reorder("").group(:crime_type).count.sort_by { |_, v| -v }.first(10).to_h
      @by_status = base_reports.reorder("").group(:status).count
      @monthly_trend = base_reports.reorder("").group("DATE_TRUNC('month', occurred_at)").count
                                   .transform_keys { |k| k&.strftime("%b %Y") }

      # Severity breakdown
      severity_labels = { 1 => "Low", 2 => "Medium", 3 => "High", 4 => "Severe", 5 => "Critical" }
      @by_severity = base_reports.to_a.group_by(&:crime_severity_level)
                                 .transform_keys { |k| severity_labels[k] || "Unknown" }
                                 .transform_values(&:count)

      # For display list, apply ordering
      @reports = base_reports.order(created_at: :desc).limit(20)
    end

    def incident_reports_bontouris
      # Reports involving tourists (BonTouris holders)
      base_reports = @scoped_reports.joins(:person_involvements)
                                    .where.not(person_involvements: { visitor_submission_id: nil })
                                    .distinct

      @total_count = base_reports.count
      @by_crime_type = base_reports.reorder("").group(:crime_type).count.sort_by { |_, v| -v }.first(10).to_h
      @by_status = base_reports.reorder("").group(:status).count
      report_ids = base_reports.pluck(:id)
      @by_nationality = PersonInvolvement.joins(:incident_report, :visitor_submission)
                                         .where(incident_reports: { id: report_ids })
                                         .group("visitor_submissions.nationality")
                                         .count.sort_by { |_, v| -v }.first(10).to_h
      @monthly_trend = base_reports.reorder("").group("DATE_TRUNC('month', occurred_at)").count
                                   .transform_keys { |k| k&.strftime("%b %Y") }

      # Severity breakdown
      severity_labels = { 1 => "Low", 2 => "Medium", 3 => "High", 4 => "Severe", 5 => "Critical" }
      @by_severity = base_reports.to_a.group_by(&:crime_severity_level)
                                 .transform_keys { |k| severity_labels[k] || "Unknown" }
                                 .transform_values(&:count)

      # For display list, apply ordering
      @reports = base_reports.order(created_at: :desc).limit(20)
    end

    private

    def set_date_range
      @period = params[:period] || "30_days"
      @end_date = Date.current
      @start_date = case @period
                    when "7_days" then 7.days.ago.to_date
                    when "30_days" then 30.days.ago.to_date
                    when "90_days" then 90.days.ago.to_date
                    when "year" then 1.year.ago.to_date
                    else 30.days.ago.to_date
                    end
    end

    def set_scope
      requested = params[:scope].presence || "personal"

      # Enforce rank ceiling: field officers cannot escalate to station/department scope.
      # analytics_scope_allowed? returns true only if requested <= officer's ceiling.
      @scope_level = if current_officer.analytics_scope_allowed?(requested)
                       requested
                     else
                       current_officer.max_analytics_scope
                     end

      # Base date-range filter, scoped to this officer's partner
      base = IncidentReport
               .where(occurred_at: @start_date..@end_date)
               .where(partner_id: current_officer.partner_id)

      @scoped_reports = case @scope_level
                        when "personal"
                          base.where(officer: current_officer)
                        when "station"
                          # Station = all officers in the same unit within this partner
                          unit_officer_ids = Officer.where(
                            partner_id: current_officer.partner_id,
                            unit_name:  current_officer.unit_name
                          ).pluck(:id)
                          base.where(officer_id: unit_officer_ids)
                        when "department"
                          # Department = all partner reports (geo scoping is Phase 2)
                          base
                        else
                          base.where(officer: current_officer)
                        end
    end

    def calculate_overview_stats
      {
        total_reports: @scoped_reports.count,
        submitted: @scoped_reports.status_submitted.count,
        approved: @scoped_reports.status_approved.count,
        rejected: @scoped_reports.status_rejected.count,
        high_severity: @scoped_reports.where(
          crime_type: CrimeConstants::CRIME_SEVERITY.select { |_, v| v >= 4 }.keys
        ).count,
        avg_per_day: (@scoped_reports.count.to_f / [(@end_date - @start_date).to_i, 1].max).round(1)
      }
    end

    def calculate_crime_breakdown
      @scoped_reports.group(:crime_type).count.sort_by { |_, v| -v }.first(10).to_h
    end

    def calculate_detailed_crime_breakdown
      counts = @scoped_reports.group(:crime_type).count
      IncidentReport::CRIME_TYPES.transform_values do |crimes|
        crimes.map { |c| { name: c, count: counts[c].to_i } }
              .select { |c| c[:count] > 0 }
      end.reject { |_, v| v.empty? }
    end

    def calculate_severity_breakdown
      labels = { 1 => "Low", 2 => "Medium", 3 => "High", 4 => "Severe", 5 => "Critical" }
      by_type = @scoped_reports.group(:crime_type).count
      result = Hash.new(0)
      by_type.each do |crime_type, count|
        severity = CrimeConstants::CRIME_SEVERITY[crime_type.to_s.downcase] || 1
        result[severity] += count
      end
      result.sort.to_h.transform_keys { |k| labels[k] || "Unknown" }
    end

    def calculate_hot_zone_data
      counts = @scoped_reports.joins(:address).where.not(addresses: { commune_id: nil })
                              .group("addresses.commune_id").count
      Commune.where(id: counts.keys).includes(:department).map do |commune|
        { commune_id: commune.id, commune_name: commune.name, department: commune.department&.name, count: counts[commune.id] }
      end.compact
    end

    def calculate_department_breakdown
      @scoped_reports.joins(:address).joins("INNER JOIN departments ON addresses.department_id = departments.id")
                     .group("departments.name").count.sort_by { |_, v| -v }
    end

    def calculate_gender_data
      PersonInvolvement.joins(:incident_report).where(incident_report: @scoped_reports)
                       .group(:sex).count.reject { |k, _| k.nil? || k.blank? }
    end

    def calculate_role_breakdown
      PersonInvolvement.joins(:incident_report).where(incident_report: @scoped_reports).group(:role).count
    end

    def calculate_geographic_by_department
      counts = @scoped_reports.joins(:address).group("addresses.department_id").count
      Department.where(id: counts.keys).map { |d| { name: d.name, count: counts[d.id].to_i } }
                .select { |d| d[:count] > 0 }.sort_by { |d| -d[:count] }
    end

    def calculate_geographic_by_commune
      @scoped_reports.joins(:address).joins("INNER JOIN communes ON addresses.commune_id = communes.id")
                     .group("communes.name").count.sort_by { |_, v| -v }.first(20)
    end

    def calculate_period_comparison
      prev_start = @start_date - (@end_date - @start_date)
      prev_end = @start_date - 1.day
      current = @scoped_reports.count
      prev = IncidentReport.where(officer: current_officer, occurred_at: prev_start..prev_end).count
      change = prev > 0 ? ((current - prev).to_f / prev * 100).round(1) : 0
      { current: current, previous: prev, change_pct: change, trend: change > 0 ? "up" : (change < 0 ? "down" : "stable") }
    end

    def calculate_daily_pattern
      @scoped_reports.group("EXTRACT(DOW FROM occurred_at)").count
                     .transform_keys { |k| %w[Sun Mon Tue Wed Thu Fri Sat][k.to_i] }
    end

    def calculate_monthly_trend
      @scoped_reports.group("DATE_TRUNC('month', occurred_at)").count
                     .transform_keys { |k| k&.strftime("%b %Y") }.sort_by { |k, _| Date.parse("01 #{k}") rescue Date.current }.to_h
    end

    def calculate_hourly_distribution
      @scoped_reports.group("EXTRACT(HOUR FROM occurred_at)").count.sort_by { |k, _| k.to_i }.to_h
    end

    def calculate_recent_trend
      (0..6).map { |d| { date: d.days.ago.to_date.strftime("%b %d"), count: @scoped_reports.where("DATE(occurred_at) = ?", d.days.ago.to_date).count } }.reverse
    end

    def calculate_performance_metrics
      my = IncidentReport.where(officer: current_officer, occurred_at: @start_date..@end_date)
      { reports_filed: my.count, approved_rate: rate(my.status_approved.count, my.count), rejected_rate: rate(my.status_rejected.count, my.count) }
    end

    def calculate_my_performance
      my = IncidentReport.where(officer: current_officer)
      { total: my.count, this_month: my.where("occurred_at >= ?", Date.current.beginning_of_month).count, approval_rate: rate(my.status_approved.count, my.count) }
    end

    def calculate_comparison_to_average
      peers = Officer.where(partner_id: current_officer.partner_id).where.not(id: current_officer.id)
      return {} if peers.empty?
      avg = peers.map { |o| IncidentReport.where(officer: o, occurred_at: @start_date..@end_date).count }.sum.to_f / peers.count
      my = @scoped_reports.where(officer: current_officer).count
      { my_count: my, station_avg: avg.round(1), diff: (my - avg).round(1) }
    end

    def calculate_resolution_rates
      my = IncidentReport.where(officer: current_officer, occurred_at: @start_date..@end_date)
      { total: my.count, approved: my.status_approved.count, rejected: my.status_rejected.count, pending: my.status_submitted.count }
    end

    def crime_pie_data
      calculate_crime_breakdown.map { |c, n| { label: c, value: n } }
    end

    def timeline_data
      calculate_monthly_trend.map { |m, c| { x: m, y: c } }
    end

    def rate(num, den)
      den.zero? ? 0 : ((num.to_f / den) * 100).round(1)
    end

    # Seasonal Analytics Methods
    def season_case_sql
      Arel.sql("CASE
        WHEN EXTRACT(MONTH FROM occurred_at) IN (12, 1, 2) THEN 'Winter'
        WHEN EXTRACT(MONTH FROM occurred_at) IN (3, 4, 5) THEN 'Spring'
        WHEN EXTRACT(MONTH FROM occurred_at) IN (6, 7, 8) THEN 'Summer'
        WHEN EXTRACT(MONTH FROM occurred_at) IN (9, 10, 11) THEN 'Fall'
      END")
    end

    def calculate_seasonal_breakdown
      @scoped_reports.group(season_case_sql).count.compact
    end

    def calculate_seasonal_crime_types
      result = {}
      %w[Winter Spring Summer Fall].each do |season|
        months = case season
                 when "Winter" then [12, 1, 2]
                 when "Spring" then [3, 4, 5]
                 when "Summer" then [6, 7, 8]
                 when "Fall" then [9, 10, 11]
                 end
        result[season] = @scoped_reports
                           .where("EXTRACT(MONTH FROM occurred_at) IN (?)", months)
                           .group(:crime_type).count
                           .sort_by { |_, v| -v }.first(5).to_h
      end
      result
    end

    def calculate_seasonal_yoy
      current_year = Date.current.year
      result = {}
      [current_year, current_year - 1].each do |year|
        result[year] = @scoped_reports
                         .where("EXTRACT(YEAR FROM occurred_at) = ?", year)
                         .group(season_case_sql).count.compact
      end
      result
    end

    def calculate_seasonal_severity
      labels = { 1 => "Low", 2 => "Medium", 3 => "High", 4 => "Severe", 5 => "Critical" }
      result = {}
      %w[Winter Spring Summer Fall].each do |season|
        months = case season
                 when "Winter" then [12, 1, 2]
                 when "Spring" then [3, 4, 5]
                 when "Summer" then [6, 7, 8]
                 when "Fall" then [9, 10, 11]
                 end
        by_type = @scoped_reports.where("EXTRACT(MONTH FROM occurred_at) IN (?)", months)
                                .group(:crime_type).count
        severity_counts = Hash.new(0)
        by_type.each do |crime_type, count|
          severity = CrimeConstants::CRIME_SEVERITY[crime_type.to_s.downcase] || 1
          severity_counts[severity] += count
        end
        result[season] = severity_counts
      end
      result
    end
  end
end
