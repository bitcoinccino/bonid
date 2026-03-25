# app/services/incident_intelligence_service.rb
# Smart incident report analysis and recommendations
class IncidentIntelligenceService
  attr_reader :incident_report

  def initialize(incident_report)
    @incident_report = incident_report
  end

  # === Severity Calculation ===
  # Dynamically calculate severity based on crime type + context
  def calculated_severity
    base = crime_type_record&.base_severity || default_severity
    modifiers = calculate_severity_modifiers
    [base + modifiers, 5].min  # Cap at 5
  end

  def calculate_severity_modifiers
    modifiers = 0

    # Multiple victims = higher severity
    victim_count = incident_report.person_involvements.role_victim.count
    modifiers += 1 if victim_count >= 2
    modifiers += 1 if victim_count >= 5

    # Minor involved
    modifiers += 1 if involves_minor?

    # Weapon mentioned in description
    modifiers += 1 if weapon_mentioned?

    # Multiple suspects = organized
    suspect_count = incident_report.person_involvements.role_suspect.count
    modifiers += 1 if suspect_count >= 3

    modifiers
  end

  # === Related Incidents ===
  # Find potentially related incidents for case linking
  def find_related_incidents(limit: 10)
    candidates = []

    # Same suspects (by BonID)
    suspect_bonids = incident_report.person_involvements.role_suspect.pluck(:bonid).compact
    if suspect_bonids.any?
      candidates += IncidentReport
        .joins(:person_involvements)
        .where(person_involvements: { bonid: suspect_bonids, role: :suspect })
        .where.not(id: incident_report.id)
        .distinct
        .limit(limit)
        .to_a
    end

    # Same location (commune) + same crime category + recent
    if incident_report.address&.commune_id
      candidates += IncidentReport
        .joins(:address)
        .where(addresses: { commune_id: incident_report.address.commune_id })
        .where(crime_type: related_crime_types)
        .where("occurred_at > ?", 30.days.ago)
        .where.not(id: incident_report.id)
        .order(occurred_at: :desc)
        .limit(limit)
        .to_a
    end

    # Same victim (by BonID)
    victim_bonids = incident_report.person_involvements.role_victim.pluck(:bonid).compact
    if victim_bonids.any?
      candidates += IncidentReport
        .joins(:person_involvements)
        .where(person_involvements: { bonid: victim_bonids, role: :victim })
        .where.not(id: incident_report.id)
        .distinct
        .limit(limit)
        .to_a
    end

    # Deduplicate and score
    score_and_rank_candidates(candidates.uniq).first(limit)
  end

  # === Suspect Matching ===
  # Find suspects across incidents that might be the same person
  def find_matching_suspects
    no_bonid_suspects = incident_report.person_involvements.role_suspect.where(no_bonid: true)

    no_bonid_suspects.map do |suspect|
      matches = find_suspect_matches(suspect)
      { suspect: suspect, matches: matches } if matches.any?
    end.compact
  end

  # === Priority Scoring ===
  # Calculate priority for review queue
  def priority_score
    score = 0

    # Base on severity
    score += calculated_severity * 20

    # Urgency factors
    score += 30 if crime_category_code == "VIOLENT"
    score += 20 if involves_minor?
    score += 15 if suspect_at_large?
    score += 10 if recent_incident?  # Within 24 hours

    # Reduce priority for drafts
    score -= 50 if incident_report.status_draft?

    [score, 0].max
  end

  # === Auto-Classification Suggestions ===
  # Suggest crime type based on description
  def suggest_crime_types(limit: 5)
    return [] unless incident_report.description.present?

    keywords = extract_keywords(incident_report.description)

    CrimeType.where(active: true).select do |crime_type|
      keyword_match_score(crime_type, keywords) > 0.3
    end.sort_by { |ct| -keyword_match_score(ct, keywords) }.first(limit)
  end

  # === Alerts Check ===
  # Check if any involved persons have active alerts
  def check_suspect_alerts
    bonids = incident_report.person_involvements.pluck(:bonid).compact
    return [] if bonids.empty?

    SuspectAlert.where(active: true, bonid: bonids).to_a
  end

  private

  def crime_type_record
    @crime_type_record ||= CrimeType.find_by(code: crime_code)
  end

  def crime_code
    IncidentReport::CRIME_CODES[incident_report.crime_type&.downcase] || "UNKN"
  end

  def crime_category_code
    crime_type_record&.crime_category&.code
  end

  def default_severity
    # Fallback severity based on category
    case crime_category_code
    when "VIOLENT" then 4
    when "ORGANIZED" then 4
    when "PROPERTY" then 2
    when "TRAFFIC" then 1
    else 2
    end
  end

  def involves_minor?
    incident_report.person_involvements.any? do |pi|
      pi.date_of_birth.present? && pi.date_of_birth > 18.years.ago
    end
  end

  def weapon_mentioned?
    return false unless incident_report.description.present?

    weapon_keywords = %w[gun firearm knife machete weapon armed pistol rifle shot blade]
    description_lower = incident_report.description.downcase
    weapon_keywords.any? { |w| description_lower.include?(w) }
  end

  def suspect_at_large?
    incident_report.person_involvements.role_suspect.any? do |s|
      s.status.in?(%w[fugitive wanted at_large escaped_custody])
    end
  end

  def recent_incident?
    incident_report.occurred_at.present? && incident_report.occurred_at > 24.hours.ago
  end

  def related_crime_types
    return [] unless crime_type_record

    related_ids = RelatedCrimeType
      .where(crime_type: crime_type_record)
      .pluck(:related_crime_type_id)

    CrimeType.where(id: related_ids).pluck(:name) + [incident_report.crime_type]
  end

  def score_and_rank_candidates(candidates)
    candidates.map do |c|
      {
        incident: c,
        score: calculate_match_score(c)
      }
    end.sort_by { |x| -x[:score] }.map { |x| x[:incident] }
  end

  def calculate_match_score(candidate)
    score = 0

    # Same suspect = high score
    our_suspects = incident_report.person_involvements.role_suspect.pluck(:bonid).compact
    their_suspects = candidate.person_involvements.role_suspect.pluck(:bonid).compact
    score += 50 if (our_suspects & their_suspects).any?

    # Same location
    score += 20 if candidate.address&.commune_id == incident_report.address&.commune_id

    # Same crime type
    score += 15 if candidate.crime_type == incident_report.crime_type

    # Temporal proximity (closer = higher)
    if candidate.occurred_at && incident_report.occurred_at
      days_apart = (candidate.occurred_at - incident_report.occurred_at).abs / 1.day
      score += [15 - days_apart, 0].max
    end

    score
  end

  def find_suspect_matches(suspect)
    return [] unless suspect.first_name.present? && suspect.last_name.present?

    # Find similar names in other incidents
    PersonInvolvement
      .role_suspect
      .where.not(incident_report_id: incident_report.id)
      .where(no_bonid: true)
      .where("LOWER(first_name) = ? AND LOWER(last_name) = ?",
             suspect.first_name.downcase,
             suspect.last_name.downcase)
      .includes(:incident_report)
      .to_a
  end

  def extract_keywords(text)
    # Simple keyword extraction - could be enhanced with NLP
    text.downcase
        .gsub(/[^a-z\s]/, '')
        .split
        .reject { |w| w.length < 4 }
        .uniq
  end

  def keyword_match_score(crime_type, keywords)
    crime_words = (crime_type.name + " " + crime_type.description.to_s).downcase.split
    matches = (keywords & crime_words).count
    return 0 if keywords.empty?
    matches.to_f / keywords.count
  end
end
