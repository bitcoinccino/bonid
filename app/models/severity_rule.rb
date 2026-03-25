# app/models/severity_rule.rb
class SeverityRule < ApplicationRecord
  belongs_to :crime_type

  validates :condition_type, presence: true
  validates :severity_modifier, presence: true, numericality: { only_integer: true }

  # Condition types
  CONDITION_TYPES = %w[
    victim_count
    suspect_count
    weapon_involved
    minor_involved
    minor_victim
    organized_crime
    repeat_offender
    location_type
    time_of_day
    multiple_perpetrators
    gang_related
  ].freeze

  validates :condition_type, inclusion: { in: CONDITION_TYPES }

  # Check if this rule applies to given context
  def applies?(context = {})
    case condition_type
    when "victim_count"
      check_count_condition(context[:victim_count])
    when "suspect_count"
      check_count_condition(context[:suspect_count])
    when "weapon_involved"
      context[:weapon_involved] == true
    when "minor_involved"
      context[:minor_involved] == true
    when "organized_crime"
      context[:suspect_count].to_i >= 3
    when "repeat_offender"
      context[:repeat_offender] == true
    when "minor_victim"
      context[:minor_victim] == true || context[:minor_involved] == true
    when "multiple_perpetrators"
      context[:suspect_count].to_i >= 2
    when "gang_related"
      context[:gang_related] == true
    when "location_type"
      check_location_condition(context[:location_type])
    when "time_of_day"
      check_time_condition(context[:occurred_at])
    else
      false
    end
  end

  private

  def check_count_condition(count)
    return false unless count.present? && condition_value.present?

    min = condition_value["min"]
    max = condition_value["max"]

    count >= min.to_i && (max.nil? || count <= max.to_i)
  end

  def check_location_condition(location_type)
    return false unless condition_value.present?

    high_risk_locations = condition_value["types"] || []
    high_risk_locations.include?(location_type)
  end

  def check_time_condition(occurred_at)
    return false unless occurred_at.present? && condition_value.present?

    # Night time (10pm - 6am) might increase severity
    hour = occurred_at.hour
    night_hours = condition_value["night_hours"] || (22..23).to_a + (0..5).to_a
    night_hours.include?(hour)
  end
end
