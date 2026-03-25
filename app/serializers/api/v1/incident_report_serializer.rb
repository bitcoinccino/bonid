# frozen_string_literal: true

# app/serializers/api/v1/incident_report_serializer.rb
#
# Serializer for incident report API responses.
# Provides consistent formatting for incident report data.
#
module Api
  module V1
    class IncidentReportSerializer
      SEVERITY_LABELS = {
        1 => "Minor",
        2 => "Low",
        3 => "Moderate",
        4 => "High",
        5 => "Severe",
        6 => "Critical"
      }.freeze

      ROLE_LABELS = {
        "suspect" => "Suspect",
        "victim" => "Victim",
        "witness" => "Witness",
        "innocent" => "Innocent Party",
        "accomplice" => "Accomplice",
        "unknown" => "Unknown"
      }.freeze

      def initialize(report, options = {})
        @report = report
        @options = options
        @include_details = options[:include_details] || false
        @include_persons = options[:include_persons] || true
      end

      def as_json
        base_data.merge(conditional_data)
      end

      def to_json(*_args)
        as_json.to_json
      end

      private

      def base_data
        {
          id: @report.uuid,
          report_id: @report.report_id,
          case_number: @report.bonid_case_number,
          crime: {
            type: @report.crime_type,
            code: @report.crime_type_record&.code,
            category: determine_crime_category,
            severity: {
              level: @report.crime_severity_level,
              label: severity_label(@report.crime_severity_level)
            }
          },
          dates: {
            occurred_at: format_datetime(@report.occurred_at),
            submitted_at: format_datetime(@report.submitted_at),
            created_at: format_datetime(@report.created_at),
            updated_at: format_datetime(@report.updated_at)
          },
          status: @report.status
        }
      end

      def conditional_data
        data = {}
        data[:location] = format_location if @report.address.present?
        data[:persons_involved] = format_persons if @include_persons
        data[:details] = format_details if @include_details
        data[:legal] = format_legal_references
        data
      end

      def format_location
        addr = @report.address
        {
          street_address: addr.street_address,
          commune: addr.commune&.name,
          communal_section: addr.communal_section&.name,
          department: addr.department&.name,
          postal_code: addr.postal_code,
          coordinates: addr.latitude.present? ? {
            latitude: addr.latitude,
            longitude: addr.longitude
          } : nil,
          country: "Haiti"
        }.compact
      end

      def format_persons
        @report.person_involvements.map do |pi|
          {
            role: pi.role,
            role_label: ROLE_LABELS[pi.role] || pi.role,
            status: pi.status,
            status_label: PersonInvolvement.statuses[pi.status],
            id_type: determine_id_type(pi),
            masked_id: mask_bonid(pi.bonid),
            is_tourist: pi.tourist?,
            nationality: pi.tourist? ? pi.visitor_submission&.nationality : nil
          }.compact
        end
      end

      def format_details
        {
          description: @report.description,
          officer: format_officer,
          evidence: {
            media_count: @report.media.count,
            has_photos: @report.media.any? { |m| m.content_type.start_with?("image/") },
            has_videos: @report.media.any? { |m| m.content_type.start_with?("video/") },
            has_documents: @report.media.any? { |m| m.content_type.include?("pdf") }
          }
        }
      end

      def format_officer
        return nil unless @report.officer

        {
          badge_hash: Digest::SHA256.hexdigest(@report.officer.badge_id.to_s)[0..7],
          rank: @report.officer.rank,
          unit: @report.officer.unit_name,
          specialty: @report.officer.unit_type
        }
      end

      def format_legal_references
        {
          penal_code_articles: @report.penal_code_articles,
          jurisdiction: "Haiti National"
        }
      end

      def determine_crime_category
        IncidentReport::CRIME_TYPES.each do |category, crimes|
          return category.to_s.humanize if crimes.include?(@report.crime_type)
        end
        "Other"
      end

      def determine_id_type(pi)
        if pi.tourist?
          "BonTouris"
        elsif pi.citizen?
          "BonID"
        else
          "Unknown"
        end
      end

      def mask_bonid(bonid)
        return nil if bonid.blank?
        parts = bonid.split("-")

        if bonid.start_with?("T-")
          # BonTouris format: T-JM-1990-M-US-P-123456
          return bonid if parts.length < 6
          [parts[0], parts[1], "••••", "•", parts[-3], parts[-2], parts[-1]].join("-")
        else
          # Citizen BonID format: DV-1989-M-SE-P8697XDS
          return bonid if parts.length < 4
          "#{parts.first}-****-*-**-#{parts.last[0]}****#{parts.last[-3..]}"
        end
      end

      def severity_label(level)
        SEVERITY_LABELS[level.to_i] || "Unknown"
      end

      def format_datetime(value)
        return nil if value.blank?
        value.iso8601
      end
    end
  end
end
