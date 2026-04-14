# frozen_string_literal: true

# Haiti's diplomatic missions worldwide — used by election system
# for consulate voting stations and diaspora channel mapping.
#
# Source: Wikipedia — Diplomatic missions of Haiti
# Updated: 2026-03-27
module HaitianDiplomaticMissions
  extend ActiveSupport::Concern

  # ── UNITED STATES ──────────────────────────────────────────────
  US_MISSIONS = [
    { id: "HT-EMB-WAS", name: "Washington, D.C.", type: "embassy", country: "US", region: "north_america" },
    { id: "HT-CON-ATL", name: "Atlanta, GA", type: "consulate_general", country: "US", region: "north_america" },
    { id: "HT-CON-BOS", name: "Boston, MA", type: "consulate_general", country: "US", region: "north_america" },
    { id: "HT-CON-CHI", name: "Chicago, IL", type: "consulate_general", country: "US", region: "north_america" },
    { id: "HT-CON-MIA", name: "Miami, FL", type: "consulate_general", country: "US", region: "north_america" },
    { id: "HT-CON-NYC", name: "New York, NY", type: "consulate_general", country: "US", region: "north_america" },
    { id: "HT-CON-ORL", name: "Orlando, FL", type: "consulate_general", country: "US", region: "north_america" },
  ].freeze

  # ── DOMINICAN REPUBLIC ─────────────────────────────────────────
  DR_MISSIONS = [
    { id: "HT-EMB-SDQ", name: "Santo Domingo", type: "embassy", country: "DO", region: "caribbean" },
    { id: "HT-CON-BAR", name: "Barahona", type: "consulate_general", country: "DO", region: "caribbean" },
    { id: "HT-CON-DAJ", name: "Dajabón", type: "consulate_general", country: "DO", region: "caribbean" },
    { id: "HT-CON-HIG", name: "Higüey", type: "consulate_general", country: "DO", region: "caribbean" },
    { id: "HT-CON-STI", name: "Santiago de los Caballeros", type: "consulate_general", country: "DO", region: "caribbean" },
  ].freeze

  # ── OTHER AMERICAS ─────────────────────────────────────────────
  AMERICAS_MISSIONS = [
    { id: "HT-EMB-BUE", name: "Buenos Aires", type: "embassy", country: "AR", region: "south_america" },
    { id: "HT-EMB-NAS", name: "Nassau", type: "embassy", country: "BS", region: "caribbean" },
    { id: "HT-EMB-BSB", name: "Brasília", type: "embassy", country: "BR", region: "south_america" },
    { id: "HT-EMB-OTT", name: "Ottawa", type: "embassy", country: "CA", region: "north_america" },
    { id: "HT-CON-MTL", name: "Montréal, QC", type: "consulate_general", country: "CA", region: "north_america" },
    { id: "HT-EMB-SCL", name: "Santiago de Chile", type: "embassy", country: "CL", region: "south_america" },
    { id: "HT-EMB-BOG", name: "Bogotá", type: "embassy", country: "CO", region: "south_america" },
    { id: "HT-EMB-HAV", name: "La Havane", type: "embassy", country: "CU", region: "caribbean" },
    { id: "HT-EMB-UIO", name: "Quito", type: "embassy", country: "EC", region: "south_america" },
    { id: "HT-EMB-MEX", name: "Mexico City", type: "embassy", country: "MX", region: "north_america" },
    { id: "HT-EMB-PTY", name: "Panama City", type: "embassy", country: "PA", region: "central_america" },
    { id: "HT-CON-PBM", name: "Paramaribo", type: "consulate_general", country: "SR", region: "south_america" },
    { id: "HT-EMB-CCS", name: "Caracas", type: "embassy", country: "VE", region: "south_america" },
  ].freeze

  # ── EUROPE & OTHER ─────────────────────────────────────────────
  EUROPE_OTHER_MISSIONS = [
    { id: "HT-EMB-BRU", name: "Bruxelles", type: "embassy", country: "BE", region: "europe" },
    { id: "HT-EMB-PAR", name: "Paris", type: "embassy", country: "FR", region: "europe" },
    { id: "HT-CON-PAR", name: "Paris (Consulat)", type: "consulate_general", country: "FR", region: "europe" },
    { id: "HT-CON-CAY", name: "Cayenne, Guyane", type: "consulate_general", country: "GF", region: "south_america" },
    { id: "HT-CON-PTP", name: "Pointe-à-Pitre, Guadeloupe", type: "consulate", country: "GP", region: "caribbean" },
    { id: "HT-EMB-BER", name: "Berlin", type: "embassy", country: "DE", region: "europe" },
    { id: "HT-EMB-ROM", name: "Rome (Saint-Siège)", type: "embassy", country: "VA", region: "europe" },
    { id: "HT-EMB-ROM2", name: "Rome (Italie)", type: "embassy", country: "IT", region: "europe" },
    { id: "HT-CON-WIL", name: "Willemstad, Curaçao", type: "consulate_general", country: "CW", region: "caribbean" },
    { id: "HT-CON-ORA", name: "Oranjestad, Aruba", type: "consulate_general", country: "AW", region: "caribbean" },
    { id: "HT-EMB-MAD", name: "Madrid", type: "embassy", country: "ES", region: "europe" },
    { id: "HT-EMB-LON", name: "London", type: "embassy", country: "GB", region: "europe" },
    { id: "HT-CON-TCI", name: "Providenciales, Turks & Caicos", type: "consulate_general", country: "TC", region: "caribbean" },
    { id: "HT-EMB-TYO", name: "Tokyo", type: "embassy", country: "JP", region: "asia" },
    { id: "HT-EMB-DOH", name: "Doha", type: "embassy", country: "QA", region: "middle_east" },
    { id: "HT-EMB-TPE", name: "Taipei", type: "embassy", country: "TW", region: "asia" },
    { id: "HT-EMB-HAN", name: "Hanoi", type: "embassy", country: "VN", region: "asia" },
  ].freeze

  # ── ALL MISSIONS ───────────────────────────────────────────────
  ALL_MISSIONS = (US_MISSIONS + DR_MISSIONS + AMERICAS_MISSIONS + EUROPE_OTHER_MISSIONS).freeze

  # Voting stations — consulates and embassies that can host diaspora voting
  VOTING_STATIONS = ALL_MISSIONS.freeze

  # Regions for grouping
  REGIONS = {
    "north_america" => "Amerik di Nò",
    "caribbean"     => "Karayib",
    "south_america" => "Amerik di Sid",
    "central_america" => "Amerik Santral",
    "europe"        => "Ewòp",
    "asia"          => "Azi",
    "middle_east"   => "Mwayen Oryan"
  }.freeze

  # Mission types
  MISSION_TYPES = {
    "embassy"           => "Anbasad",
    "consulate_general" => "Konsila Jeneral",
    "consulate"         => "Konsila"
  }.freeze

  class_methods do
    def missions_by_country(country_code)
      ALL_MISSIONS.select { |m| m[:country] == country_code }
    end

    def missions_by_region(region)
      ALL_MISSIONS.select { |m| m[:region] == region }
    end

    def voting_countries
      ALL_MISSIONS.map { |m| m[:country] }.uniq.sort
    end
  end

  # Priority country codes for dropdowns — ordered by diaspora population size.
  # Countries with Haitian diplomatic missions + key diaspora territories.
  PRIORITY_COUNTRY_CODES = %w[
    HT US DO CA FR BR BS CL MX CU JM
    GP MQ GF TT PA CO EC VE AR SR
    BE DE ES GB IT JP QA TW
  ].freeze
end
