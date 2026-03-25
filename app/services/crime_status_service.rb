# frozen_string_literal: true

# app/services/crime_status_service.rb
#
# Service to check crime involvement status for BonID/BonTouris holders.
# Provides tiered access based on partner permissions.
#
# Access Tiers:
# - Tier 1 (Basic): has_record (yes/no), severity_level (if yes)
# - Tier 2 (Summary): + involvement count, roles, latest incident date, status breakdown
# - Tier 3 (Full): + incident details, person status history (requires citizen consent)
#
# Usage:
#   result = CrimeStatusService.new(
#     bonid: "JM-1968-M-OUEST-P2334-217",
#     partner: partner,
#     access_tier: :tier_2
#   ).call
#
#   if result[:success]
#     puts result[:data]
#   else
#     puts result[:error]
#   end
#
class CrimeStatusService
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
    "unknown" => "Unknown Role"
  }.freeze

  def initialize(bonid:, partner:, access_tier: :tier_1)
    @bonid = bonid.to_s.strip.upcase
    @partner = partner
    @access_tier = access_tier.to_sym
  end

  def call
    # Find person by BonID or BonTouris
    person_result = find_person
    return person_result unless person_result[:success]

    @person = person_result[:person]
    @person_type = person_result[:person_type]

    # Get all crime involvements
    involvements = find_involvements

    # Build response based on access tier
    case @access_tier
    when :tier_1
      build_tier_1_response(involvements)
    when :tier_2
      build_tier_2_response(involvements)
    when :tier_3
      build_tier_3_response(involvements)
    else
      build_tier_1_response(involvements)
    end
  rescue StandardError => e
    Rails.logger.error("[CrimeStatusService] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    { success: false, error: "Internal error processing request", code: 500, status: :internal_server_error }
  end

  private

  # Find person by BonID (citizen) or BonTouris (tourist)
  def find_person
    # Try citizen lookup first
    user = User.find_by(bonid: @bonid)
    if user
      return { success: true, person: user, person_type: :citizen }
    end

    # Try tourist lookup
    visitor = VisitorSubmission.approved.find_by(bonid: @bonid)
    if visitor
      return { success: true, person: visitor, person_type: :tourist }
    end

    # Try 6-digit suffix lookup
    if @bonid.match?(/^\d{6}$/)
      # Search citizens by suffix
      user = User.where("bonid LIKE ?", "%-#{@bonid[0..3]}-#{@bonid[4..5]}%").first
      if user
        return { success: true, person: user, person_type: :citizen }
      end

      # Search tourists by suffix
      visitor = VisitorSubmission.approved.where("bonid LIKE ?", "%-#{@bonid}").first
      if visitor
        return { success: true, person: visitor, person_type: :tourist }
      end
    end

    { success: false, error: "BonID not found or not verified", code: 404, status: :not_found }
  end

  # Find all person involvements in incident reports
  def find_involvements
    if @person_type == :citizen
      PersonInvolvement.includes(incident_report: [:officer, :crime_type_record, :address])
                       .where(user_id: @person.id)
                       .or(PersonInvolvement.where(bonid: @person.bonid))
                       .joins(:incident_report)
                       .order("incident_reports.occurred_at DESC")
    else
      PersonInvolvement.includes(incident_report: [:officer, :crime_type_record, :address])
                       .where(visitor_submission_id: @person.id)
                       .or(PersonInvolvement.where(bonid: @person.bonid))
                       .joins(:incident_report)
                       .order("incident_reports.occurred_at DESC")
    end
  end

  # Tier 1: Basic yes/no with severity level
  #
  # has_criminal_record is TRUE only when the person is a suspect or accomplice.
  # Being a victim, witness, or innocent party does NOT constitute a criminal record.
  def build_tier_1_response(involvements)
    # Only suspect/accomplice roles constitute a criminal record
    suspect_involvements = involvements.select { |pi| pi.role_suspect? || pi.role_accomplice? }
    has_record = suspect_involvements.any?

    data = {
      has_criminal_record: has_record,
      has_involvements: involvements.any?,
      person_type: @person_type.to_s,
      checked_at: Time.current.iso8601
    }

    if involvements.any?
      max_severity = involvements.map { |pi| pi.incident_report.crime_severity_level }.max || 1
      data[:highest_severity_level] = max_severity
      data[:severity_label] = SEVERITY_LABELS[max_severity] || "Unknown"

      # Suspect-specific risk indicators
      data[:is_suspect_in_any] = has_record
      data[:active_warrants] = has_record && suspect_involvements.any? { |pi| pi.status_wanted? || pi.status_fugitive? }

      # Role breakdown so the consumer knows WHY this person appears
      data[:roles] = involvements.map(&:role).uniq
    end

    { success: true, data: data }
  end

  # Tier 2: Summary with counts and role breakdown
  def build_tier_2_response(involvements)
    has_record = involvements.any?

    data = build_tier_1_response(involvements)[:data]

    if has_record
      # Count by role
      role_counts = involvements.group_by(&:role).transform_values(&:count)
      data[:involvement_count] = involvements.count
      data[:role_breakdown] = role_counts.transform_keys { |k| ROLE_LABELS[k] || k }

      # Status summary for suspect roles
      suspect_statuses = involvements.select { |pi| pi.role_suspect? || pi.role_accomplice? }
                                     .group_by(&:status)
                                     .transform_values(&:count)
      data[:suspect_statuses] = suspect_statuses unless suspect_statuses.empty?

      # Date range
      dates = involvements.map { |pi| pi.incident_report.occurred_at }.compact
      if dates.any?
        data[:earliest_incident] = dates.min.iso8601
        data[:latest_incident] = dates.max.iso8601
      end

      # Crime type summary
      crime_types = involvements.map { |pi| pi.incident_report.crime_type }.compact.tally
      data[:crime_types] = crime_types.sort_by { |_, v| -v }.first(5).to_h

      # Severity distribution
      severity_dist = involvements.map { |pi| pi.incident_report.crime_severity_level }
                                   .tally
                                   .transform_keys { |k| SEVERITY_LABELS[k] || "Level #{k}" }
      data[:severity_distribution] = severity_dist
    end

    { success: true, data: data }
  end

  # Tier 3: Full details (requires consent)
  def build_tier_3_response(involvements)
    data = build_tier_2_response(involvements)[:data]

    if involvements.any?
      # Detailed incident list
      data[:incidents] = involvements.map do |pi|
        report = pi.incident_report
        {
          id: report.uuid,
          report_id: report.report_id,
          case_number: report.bonid_case_number,
          crime_type: report.crime_type,
          crime_code: report.crime_type_record&.code || CrimeType.find_by(name: report.crime_type)&.code,
          severity: report.crime_severity_level,
          severity_label: SEVERITY_LABELS[report.crime_severity_level],
          occurred_at: report.occurred_at&.iso8601,
          submitted_at: report.submitted_at&.iso8601,
          report_status: report.status,
          involvement: {
            role: pi.role,
            role_label: ROLE_LABELS[pi.role],
            status: pi.status,
            status_label: PersonInvolvement.statuses[pi.status]
          },
          location: build_location(report),
          officer: build_officer_info(report),
          penal_code: report.penal_code_articles
        }
      end

      # Timeline view
      data[:timeline] = build_timeline(involvements)

      # Current risk assessment
      data[:risk_assessment] = build_risk_assessment(involvements)
    end

    { success: true, data: data }
  end

  # Build location info
  def build_location(report)
    return nil unless report.address

    {
      commune: report.address.commune&.name,
      communal_section: report.address.communal_section&.name,
      department: report.address.department&.name,
      country: "Haiti"
    }
  end

  # Build officer info (limited for privacy)
  def build_officer_info(report)
    return nil unless report.officer

    {
      unit: report.officer.unit_name,
      badge_hash: Digest::SHA256.hexdigest(report.officer.badge_id.to_s)[0..7]
    }
  end

  # Build timeline of events
  def build_timeline(involvements)
    involvements.map do |pi|
      report = pi.incident_report
      {
        date: report.occurred_at&.strftime("%Y-%m-%d"),
        event: "#{pi.role.humanize} in #{report.crime_type}",
        status: pi.status,
        severity: report.crime_severity_level
      }
    end
  end

  # Build risk assessment
  def build_risk_assessment(involvements)
    suspect_involvements = involvements.select { |pi| pi.role_suspect? || pi.role_accomplice? }

    return { risk_level: "none", score: 0 } if suspect_involvements.empty?

    # Calculate risk score (0-100)
    score = 0

    # Factor 1: Number of incidents (max 30 points)
    score += [suspect_involvements.count * 5, 30].min

    # Factor 2: Severity of crimes (max 30 points)
    max_severity = suspect_involvements.map { |pi| pi.incident_report.crime_severity_level }.max || 1
    score += max_severity * 5

    # Factor 3: Recency (max 20 points)
    latest = suspect_involvements.map { |pi| pi.incident_report.occurred_at }.compact.max
    if latest
      days_ago = (Date.current - latest.to_date).to_i
      score += case days_ago
               when 0..30 then 20
               when 31..90 then 15
               when 91..180 then 10
               when 181..365 then 5
               else 0
               end
    end

    # Factor 4: Current status (max 20 points)
    if suspect_involvements.any? { |pi| pi.status_wanted? || pi.status_fugitive? }
      score += 20
    elsif suspect_involvements.any? { |pi| pi.status_armed? || pi.status_dangerous? }
      score += 15
    elsif suspect_involvements.any? { |pi| pi.status_under_surveillance? }
      score += 10
    end

    # Determine risk level
    risk_level = case score
                 when 0..20 then "low"
                 when 21..40 then "moderate"
                 when 41..60 then "elevated"
                 when 61..80 then "high"
                 else "critical"
                 end

    {
      risk_level: risk_level,
      score: [score, 100].min,
      factors: {
        incident_count: suspect_involvements.count,
        max_severity: max_severity,
        has_active_warrant: suspect_involvements.any? { |pi| pi.status_wanted? || pi.status_fugitive? },
        is_armed_or_dangerous: suspect_involvements.any? { |pi| pi.status_armed? || pi.status_dangerous? }
      }
    }
  end
end
