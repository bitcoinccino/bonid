# app/models/crime_hotspot.rb
class CrimeHotspot < ApplicationRecord
  belongs_to :commune
  belongs_to :crime_category, optional: true

  validates :period_start, presence: true
  validates :period_end, presence: true
  validates :commune_id, uniqueness: { scope: [:period_start, :period_end, :crime_category_id] }

  scope :recent, -> { order(period_end: :desc) }
  scope :current_period, -> { where(period_end: Date.current) }
  scope :high_severity, -> { where("severity_score >= ?", 100) }
  scope :trending_up, -> { where("trend_percentage > ?", 10) }
  scope :trending_down, -> { where("trend_percentage < ?", -10) }

  # Get top hotspots for a period
  def self.top_hotspots(limit: 10, period_end: Date.current)
    where(period_end: period_end)
      .order(severity_score: :desc)
      .limit(limit)
  end

  # Calculate trend from previous period
  def calculate_trend(previous_hotspot)
    return nil unless previous_hotspot.present? && previous_hotspot.incident_count > 0

    change = incident_count - previous_hotspot.incident_count
    (change.to_f / previous_hotspot.incident_count * 100).round(1)
  end

  def severity_level
    case severity_score
    when 0..50 then "Low"
    when 51..100 then "Moderate"
    when 101..200 then "High"
    else "Critical"
    end
  end

  def severity_color
    case severity_score
    when 0..50 then "success"
    when 51..100 then "warning"
    when 101..200 then "danger"
    else "dark"
    end
  end

  def top_crimes(limit: 5)
    return [] unless breakdown.present?

    breakdown.sort_by { |_, count| -count }.first(limit).to_h
  end
end
