# frozen_string_literal: true

# app/serializers/api/v1/crime_status_serializer.rb
#
# Serializer for crime status API responses.
# Provides consistent formatting for crime involvement data.
#
module Api
  module V1
    class CrimeStatusSerializer
      SEVERITY_LABELS = {
        1 => "Minor",
        2 => "Low",
        3 => "Moderate",
        4 => "High",
        5 => "Severe",
        6 => "Critical"
      }.freeze

      def initialize(data, options = {})
        @data = data
        @options = options
        @bonid = options[:bonid]
        @partner = options[:partner]
        @access_tier = options[:access_tier] || :tier_1
      end

      def as_json
        {
          status: "success",
          bonid: @bonid,
          crime_status: format_crime_status,
          partner: @partner&.name,
          access_tier: @access_tier,
          timestamp: Time.current.iso8601,
          api_version: "1.0.0"
        }
      end

      def to_json(*_args)
        as_json.to_json
      end

      private

      def format_crime_status
        return @data if @data.is_a?(Hash)

        # Handle raw data formatting
        {
          has_criminal_record: @data[:has_criminal_record] || false,
          person_type: @data[:person_type],
          checked_at: @data[:checked_at] || Time.current.iso8601
        }.merge(format_tier_specific_data)
      end

      def format_tier_specific_data
        case @access_tier
        when :tier_1
          format_tier_1_data
        when :tier_2
          format_tier_1_data.merge(format_tier_2_data)
        when :tier_3
          format_tier_1_data.merge(format_tier_2_data).merge(format_tier_3_data)
        else
          format_tier_1_data
        end
      end

      def format_tier_1_data
        return {} unless @data[:has_criminal_record]

        {
          highest_severity_level: @data[:highest_severity_level],
          severity_label: severity_label(@data[:highest_severity_level]),
          is_suspect_in_any: @data[:is_suspect_in_any] || false,
          active_warrants: @data[:active_warrants] || false
        }
      end

      def format_tier_2_data
        return {} unless @data[:has_criminal_record]

        {
          involvement_count: @data[:involvement_count] || 0,
          role_breakdown: @data[:role_breakdown] || {},
          suspect_statuses: @data[:suspect_statuses] || {},
          earliest_incident: @data[:earliest_incident],
          latest_incident: @data[:latest_incident],
          crime_types: @data[:crime_types] || {},
          severity_distribution: @data[:severity_distribution] || {}
        }.compact
      end

      def format_tier_3_data
        return {} unless @data[:has_criminal_record]

        {
          incidents: format_incidents(@data[:incidents] || []),
          timeline: @data[:timeline] || [],
          risk_assessment: @data[:risk_assessment] || {}
        }.compact
      end

      def format_incidents(incidents)
        incidents.map do |incident|
          {
            id: incident[:id],
            report_id: incident[:report_id],
            case_number: incident[:case_number],
            crime_type: incident[:crime_type],
            crime_code: incident[:crime_code],
            severity: incident[:severity],
            severity_label: severity_label(incident[:severity]),
            occurred_at: format_datetime(incident[:occurred_at]),
            submitted_at: format_datetime(incident[:submitted_at]),
            report_status: incident[:report_status],
            involvement: incident[:involvement],
            location: incident[:location],
            penal_code: incident[:penal_code]
          }.compact
        end
      end

      def severity_label(level)
        SEVERITY_LABELS[level.to_i] || "Unknown"
      end

      def format_datetime(value)
        return nil if value.blank?
        return value if value.is_a?(String)
        value.iso8601
      end
    end
  end
end
