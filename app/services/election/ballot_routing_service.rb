# frozen_string_literal: true

# Routes voters to the correct ballot based on their BonID location segment.
#
# Domestic voters (Haiti): get presidential + senate + deputy for their department
# Diaspora voters (abroad): get presidential/national ballot only
#
# The location segment is the 4th part of the BonID:
#   VP-1970-M-ND-P2334-4EC  →  "ND" = Nord department (domestic)
#   VP-1970-M-US-P2334-4EC  →  "US" = United States (diaspora)
#
# Haiti has 10 departments, each with senate + deputy seats:
#   OU (Ouest), ND (Nord), SD (Sud), AR (Artibonite), NE (Nord-Est),
#   NO (Nord-Ouest), SE (Sud-Est), CE (Centre), GA (Grande-Anse), NI (Nippes)
#
module Election
  class BallotRoutingService
    # Haitian department codes → full names
    DEPARTMENTS = {
      "OU" => "Ouest",
      "ND" => "Nord",
      "SD" => "Sud",
      "AR" => "Artibonite",
      "NE" => "Nord-Est",
      "NO" => "Nord-Ouest",
      "SE" => "Sud-Est",
      "CE" => "Centre",
      "GA" => "Grande-Anse",
      "NI" => "Nippes"
    }.freeze

    # Determine the ballot type and constituency for a voter.
    #
    # @param voter [User] The verified BonID holder
    # @param election_id [String] Election identifier
    # @return [Hash] { type:, department:, ballot_sections:, location_code: }
    def self.route(voter, election_id)
      location_code = extract_location_code(voter.bonid)

      if diaspora?(location_code)
        diaspora_ballot(voter, election_id, location_code)
      else
        domestic_ballot(voter, election_id, location_code)
      end
    end

    # Check if a location code represents a diaspora voter
    def self.diaspora?(location_code)
      return true if location_code.blank?

      # If it's a valid ISO country code AND not Haiti → diaspora
      country = ISO3166::Country[location_code] rescue nil
      return true if country.present? && location_code != "HT"

      # If it's NOT a known Haitian department code → assume diaspora
      !DEPARTMENTS.key?(location_code)
    end

    private

    # Extract the location segment from a BonID
    # VP-1970-M-ND-P2334-4EC → "ND"
    def self.extract_location_code(bonid)
      parts = bonid.to_s.split("-")
      return nil if parts.length < 4
      parts[3].upcase
    end

    # Diaspora ballot: presidential/national only
    def self.diaspora_ballot(voter, election_id, location_code)
      country_name = ISO3166::Country[location_code]&.translations&.dig("en") || location_code

      {
        type: :diaspora,
        location_code: location_code,
        country: country_name,
        department: nil,
        ballot_sections: [
          {
            title: "Prezidan Repiblik",
            description: "Chwazi yon kandida pou Prezidan Repiblik d'Ayiti",
            position: "president",
            candidates: load_candidates(election_id, "president")
          }
        ],
        message: "Kòm elektè dyaspora (#{country_name}), ou ka vote pou Prezidan sèlman."
      }
    end

    # Domestic ballot: presidential + senate + deputy
    # Senate = department level, Deputy = commune/arrondissement level
    def self.domestic_ballot(voter, election_id, location_code)
      department_name = DEPARTMENTS[location_code] || location_code

      # Get commune and arrondissement from voter's address for deputy routing
      address = voter.address
      commune = address&.commune
      arrondissement = commune&.arrondissement
      communal_section = address&.communal_section

      commune_name = commune&.name || "Enkoni"
      arrondissement_name = arrondissement&.name || "Enkoni"

      sections = [
        {
          title: "Prezidan Repiblik",
          description: "Chwazi yon kandida pou Prezidan Repiblik d'Ayiti",
          position: "president",
          candidates: load_candidates(election_id, "president")
        },
        {
          title: "Senatè — #{department_name}",
          description: "Chwazi yon kandida pou Senatè depatman #{department_name}",
          position: "senator",
          department: location_code,
          candidates: load_candidates(election_id, "senator", location_code)
        },
        {
          title: "Depite — #{commune_name} (#{arrondissement_name})",
          description: "Chwazi yon kandida pou Depite sikonskripsyon #{commune_name}, arondisman #{arrondissement_name}",
          position: "deputy",
          department: location_code,
          commune: commune&.id,
          arrondissement: arrondissement&.id,
          candidates: load_candidates(election_id, "deputy", location_code, commune&.id)
        }
      ]

      {
        type: :domestic,
        location_code: location_code,
        country: "Haiti",
        department: department_name,
        commune: commune_name,
        arrondissement: arrondissement_name,
        communal_section: communal_section&.name,
        ballot_sections: sections,
        message: "Ou ap vote nan komin #{commune_name}, depatman #{department_name}: Prezidan, Senatè, ak Depite."
      }
    end

    # Load candidates for a position in an election
    # TODO: Replace with ElectionCandidate model queries
    #
    # @param election_id [String]
    # @param position [String] "president", "senator", "deputy"
    # @param department [String] Department code (for senator)
    # @param commune_id [Integer] Commune ID (for deputy — circumscription level)
    def self.load_candidates(election_id, position, department = nil, commune_id = nil)
      # Placeholder — will be populated by CEP data import
      # In production:
      #   ElectionCandidate.where(election_id:, position:)
      #     .where(department: department) if senator
      #     .where(commune_id: commune_id) if deputy
      []
    end
  end
end
