# app/models/crime_type.rb
class CrimeType < ApplicationRecord
  belongs_to :crime_category
  has_many :severity_rules, dependent: :destroy
  has_many :related_crime_types, dependent: :destroy
  has_many :related_crimes, through: :related_crime_types, source: :related_crime_type
  has_many :incident_reports, foreign_key: :crime_type_record_id

  validates :name, presence: true, uniqueness: true
  validates :code, presence: true, uniqueness: true, length: { maximum: 10 }
  validates :base_severity, inclusion: { in: 1..5 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:display_order, :name) }
  scope :by_category, ->(category_id) { where(crime_category_id: category_id) }
  scope :by_severity, ->(level) { where(base_severity: level) }
  scope :high_severity, -> { where("base_severity >= ?", 4) }

  # Get grouped options for select dropdown
  def self.grouped_for_select
    active.includes(:crime_category).ordered.group_by(&:crime_category).transform_keys(&:name)
  end

  # Find by legacy crime type string
  def self.find_by_legacy_name(name)
    find_by("LOWER(name) = ?", name.to_s.downcase)
  end

  # Calculate effective severity with context
  def effective_severity(context = {})
    base = base_severity
    modifiers = severity_rules.sum do |rule|
      rule.applies?(context) ? rule.severity_modifier : 0
    end
    [base + modifiers, 5].min
  end

  # Get related crime names for linking suggestions
  def related_crime_names
    related_crimes.active.pluck(:name)
  end

  def to_s
    name
  end

  def severity_label
    case base_severity
    when 1 then "Minor"
    when 2 then "Low"
    when 3 then "Moderate"
    when 4 then "Serious"
    when 5 then "Critical"
    else "Unknown"
    end
  end

  def severity_color
    case base_severity
    when 1 then "secondary"
    when 2 then "info"
    when 3 then "warning"
    when 4 then "danger"
    when 5 then "dark"
    else "secondary"
    end
  end
end
