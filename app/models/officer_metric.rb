# app/models/officer_metric.rb
class OfficerMetric < ApplicationRecord
  belongs_to :officer

  validates :period_start, presence: true
  validates :period_end, presence: true
  validates :officer_id, uniqueness: { scope: :period_start }

  scope :recent, -> { order(period_end: :desc) }
  scope :for_period, ->(start_date, end_date) { where(period_start: start_date, period_end: end_date) }
  scope :current_month, -> { where(period_start: Date.current.beginning_of_month) }

  # Get top performers
  def self.top_reporters(period_start:, limit: 10)
    where(period_start: period_start)
      .order(reports_submitted: :desc)
      .limit(limit)
      .includes(:officer)
  end

  def self.highest_approval_rate(period_start:, limit: 10, min_reports: 5)
    where(period_start: period_start)
      .where("reports_submitted >= ?", min_reports)
      .order(approval_rate: :desc)
      .limit(limit)
      .includes(:officer)
  end

  def rejection_rate
    return 0 if reports_submitted.zero?
    (reports_rejected.to_f / reports_submitted * 100).round(1)
  end

  def pending_count
    reports_submitted - reports_approved - reports_rejected
  end

  def most_reported_crime
    return nil unless crime_type_breakdown.present?
    crime_type_breakdown.max_by { |_, count| count }&.first
  end

  def performance_score
    # Weighted score based on volume and quality
    volume_score = [reports_submitted * 2, 100].min
    quality_score = approval_rate
    (volume_score * 0.4 + quality_score * 0.6).round(1)
  end

  def performance_level
    case performance_score
    when 0..40 then "Needs Improvement"
    when 41..60 then "Average"
    when 61..80 then "Good"
    when 81..90 then "Excellent"
    else "Outstanding"
    end
  end
end
