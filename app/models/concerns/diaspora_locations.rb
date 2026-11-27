# frozen_string_literal: true

# US State → City choices for the waitlist form's "Abroad" path. States
# with large Haitian communities are pinned first. The city field is a
# type-to-search box over every Census place in the state, with the
# curated cities below suggested first; any typed city is accepted.
# State names come from the countries gem.
module DiasporaLocations
  STATE_COUNTRY = "US"

  # Countries a citizen can pick under "Abroad" right now. Add codes here
  # to open more countries (the form and validation follow this list).
  SIGNUP_COUNTRIES = %w[US].freeze

  PRIORITY_STATES = %w[FL NY MA NJ GA IL PA MD].freeze

  CITIES = {
    "FL" => [
      "Miami", "North Miami", "North Miami Beach", "Miramar", "Pembroke Pines",
      "Fort Lauderdale", "Pompano Beach", "Boca Raton", "West Palm Beach",
      "Boynton Beach", "Delray Beach", "Orlando", "Kissimmee", "Tampa",
      "Jacksonville", "Naples", "Fort Myers"
    ],
    "NY" => [
      "Brooklyn", "Queens", "Manhattan", "Bronx", "Spring Valley", "Nyack",
      "Elmont", "Hempstead", "Uniondale", "Long Island"
    ],
    "MA" => [
      "Boston", "Brockton", "Cambridge", "Somerville", "Malden", "Everett",
      "Randolph", "Waltham"
    ],
    "NJ" => [
      "Newark", "Irvington", "East Orange", "Orange", "Elizabeth", "Linden",
      "Asbury Park", "Trenton"
    ],
    "GA" => [
      "Atlanta", "Decatur", "Stone Mountain", "Jonesboro", "Lawrenceville"
    ]
  }.freeze

  # Every Census place per state, built by `bin/rails us_cities:import`
  CITY_DATA_PATH = "config/data/us_cities.json"

  # City suggestions for a state: curated cities first (in their order),
  # then every other Census place A→Z. [] for an unknown state.
  def self.cities_for(state_code)
    code = state_code.to_s.upcase
    return [] unless states.key?(code)

    curated = CITIES.fetch(code, [])
    curated + (census_cities.fetch(code, []) - curated)
  end

  def self.census_cities
    @census_cities ||= begin
      path = Rails.root.join(CITY_DATA_PATH)
      path.exist? ? JSON.parse(path.read).freeze : {}
    end
  end

  # 50 states + DC as { "FL" => "Florida", ... }
  def self.states
    @states ||= ISO3166::Country[STATE_COUNTRY].subdivisions
                  .select { |_code, s| %w[state district].include?(s.type.to_s) }
                  .to_h { |code, s| [code, s.name] }
                  .freeze
  end

  # Two groups for the State dropdown: priority states, then the rest A→Z
  def self.state_groups
    {
      priority: PRIORITY_STATES.map { |code| [states[code], code] },
      other: states.except(*PRIORITY_STATES).map { |code, name| [name, code] }.sort_by(&:first)
    }
  end

  # [[localized name, code], ...] for the "Abroad" country dropdown
  def self.country_options
    SIGNUP_COUNTRIES.map do |code|
      country = ISO3166::Country[code]
      [I18n.t("main.signup_form.country_names.#{code}", default: country.common_name || country.name), code]
    end
  end

  def self.state_name(code) = states[code.to_s.upcase]
end
