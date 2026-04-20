# frozen_string_literal: true

# Renders a structured address into the line layout the destination country's
# postal operator expects, per UPU S42 ("International Addressing Standards").
#
# Why this exists: diaspora citizens see consulate addresses in a "find your
# voting station" locator and on mailed-back voter receipts. A US consulate
# address must read "City, ST 33130 / UNITED STATES"; a French consulate must
# read "75008 PARIS / FRANCE". One free-text blob can't do both.
#
# Coverage: explicit rules for every host country in
# HaitianDiplomaticMissions (the 25 countries with at least one Haitian
# embassy/consulate). Unknown country codes fall back to a generic format
# that renders all elements in a safe order.
#
# Usage:
#   PostalAddressFormatter.new(participation).call
#   # => "259 SW 13th St.\nMiami, FL 33130\nUNITED STATES"
#
# Or as_lines for views that want to render line-by-line:
#   PostalAddressFormatter.new(participation).as_lines
#   # => ["259 SW 13th St.", "Miami, FL 33130", "UNITED STATES"]
class PostalAddressFormatter
  # Country names in the language of the destination's postal operator.
  # UPU recommends the country line be in the SENDER's language for incoming
  # international mail, but we render in the destination's local form so the
  # display is recognizable to the diaspora citizen reading it.
  COUNTRY_NAMES = {
    "US" => "UNITED STATES",
    "DO" => "REPÚBLICA DOMINICANA",
    "AR" => "ARGENTINA",
    "BS" => "BAHAMAS",
    "BR" => "BRASIL",
    "CA" => "CANADA",
    "CL" => "CHILE",
    "CO" => "COLOMBIA",
    "CU" => "CUBA",
    "EC" => "ECUADOR",
    "MX" => "MÉXICO",
    "PA" => "PANAMÁ",
    "SR" => "SURINAME",
    "VE" => "VENEZUELA",
    "BE" => "BELGIQUE",
    "FR" => "FRANCE",
    "GF" => "FRANCE",          # Guyane française — French overseas dept
    "GP" => "FRANCE",          # Guadeloupe — French overseas dept
    "DE" => "DEUTSCHLAND",
    "VA" => "CITTÀ DEL VATICANO",
    "IT" => "ITALIA",
    "CW" => "CURAÇAO",
    "AW" => "ARUBA",
    "ES" => "ESPAÑA",
    "GB" => "UNITED KINGDOM",
    "TC" => "TURKS AND CAICOS ISLANDS",
    "JP" => "JAPAN",
    "QA" => "QATAR",
    "TW" => "TAIWAN",
    "VN" => "VIETNAM",
    "ZA" => "SOUTH AFRICA",
    "CN" => "CHINA"
  }.freeze

  def initialize(record)
    @record = record
    @country = record.respond_to?(:mission_country) ? record.mission_country : nil
  end

  # Returns the formatted address as a single string with newline separators.
  def call
    as_lines.join("\n")
  end

  # Returns the formatted address as an Array of lines (no trailing blanks).
  # Forces UTF-8 on each line because some country labels (REPÚBLICA, MÉXICO,
  # PANAMÁ, …) carry non-ASCII glyphs and can collide with ASCII-8BIT strings
  # coming from frozen literals when the record's columns mix encodings.
  def as_lines
    rule = FORMAT_RULES[@country] || GENERIC_FORMAT
    rule.call(@record)
        .reject(&:blank?)
        .map { |s| s.to_s.dup.force_encoding("UTF-8") }
  end

  private

  # Format rules per UPU S42, keyed by ISO 3166-1 alpha-2 country code.
  # Each rule receives the record and returns an Array of address lines
  # (excluding the recipient line — that's the consulate name, rendered
  # separately by the calling view).
  FORMAT_RULES = {
    # ── United States: street / "City, ST ZIP" / COUNTRY ──────────────
    "US" => ->(r) {
      city_line = [r.locality, [r.region, r.postal_code].compact_blank.join(" ")]
                    .compact_blank.join(", ")
      [r.street_line1, r.street_line2, city_line, COUNTRY_NAMES["US"]]
    },

    # ── Canada: street / "City ON  A1A 1A1" / COUNTRY ─────────────────
    # Two spaces between province and postal code per Canada Post standard.
    "CA" => ->(r) {
      city_line = [r.locality, r.region, r.postal_code].compact_blank.join(" ").squeeze(" ")
      city_line = city_line.sub(/(#{Regexp.escape(r.region.to_s)}) (#{Regexp.escape(r.postal_code.to_s)})/, '\1  \2') if r.region.present? && r.postal_code.present?
      [r.street_line1, r.street_line2, city_line, COUNTRY_NAMES["CA"]]
    },

    # ── France & overseas depts: street / "ZIP CITY" / COUNTRY ────────
    # City line in upper case per La Poste convention.
    "FR" => ->(r) { _fr_format(r, "FR") },
    "GF" => ->(r) { _fr_format(r, "GF") },
    "GP" => ->(r) { _fr_format(r, "GP") },

    # ── DR, ES, MX, IT, AR, CL, EC, VE, CO, PA, BS, CU: "City, postal" ─
    # Latin-American & Iberian convention — postal after city, comma sep.
    "DO" => ->(r) { _city_comma_postal(r, "DO") },
    "ES" => ->(r) { _city_comma_postal(r, "ES") },
    "MX" => ->(r) { _city_comma_postal(r, "MX") },
    "IT" => ->(r) { _italy_format(r) },
    "AR" => ->(r) { _city_comma_postal(r, "AR") },
    "CL" => ->(r) { _city_comma_postal(r, "CL") },
    "EC" => ->(r) { _city_comma_postal(r, "EC") },
    "VE" => ->(r) { _city_comma_postal(r, "VE") },
    "CO" => ->(r) { _city_comma_postal(r, "CO") },
    "PA" => ->(r) { _city_comma_postal(r, "PA") },
    "BS" => ->(r) { _city_comma_postal(r, "BS") },
    "CU" => ->(r) { _city_comma_postal(r, "CU") },

    # ── Brazil: street / locality - region / postal / COUNTRY ─────────
    "BR" => ->(r) {
      locality_region = [r.locality, r.region].compact_blank.join(" - ")
      [r.street_line1, r.street_line2, locality_region, r.postal_code, COUNTRY_NAMES["BR"]]
    },

    # ── Suriname: street / locality / COUNTRY (no postal in use) ──────
    "SR" => ->(r) { [r.street_line1, r.street_line2, r.locality, COUNTRY_NAMES["SR"]] },

    # ── Belgium / Germany: street / "ZIP CITY" / COUNTRY ──────────────
    "BE" => ->(r) { _zip_then_city(r, "BE") },
    "DE" => ->(r) { _zip_then_city(r, "DE") },

    # ── Vatican / UK: street / city / postal / COUNTRY ────────────────
    "VA" => ->(r) {
      [r.street_line1, r.street_line2, r.locality, r.postal_code, COUNTRY_NAMES["VA"]]
    },
    # UK: street / locality / region(county) / postcode / COUNTRY
    "GB" => ->(r) {
      [r.street_line1, r.street_line2, r.locality, r.region, r.postal_code, COUNTRY_NAMES["GB"]]
    },

    # ── Curaçao / Aruba / Turks & Caicos: street / city / COUNTRY ─────
    "CW" => ->(r) { [r.street_line1, r.street_line2, r.locality, COUNTRY_NAMES["CW"]] },
    "AW" => ->(r) { [r.street_line1, r.street_line2, r.locality, COUNTRY_NAMES["AW"]] },
    "TC" => ->(r) { [r.street_line1, r.street_line2, r.locality, COUNTRY_NAMES["TC"]] },

    # ── Japan: postal / region / locality / street / COUNTRY ──────────
    # Japan Post addresses are largest-to-smallest in Japanese, but the
    # international form goes smallest-to-largest. We render the int'l form.
    "JP" => ->(r) {
      [r.street_line1, r.street_line2, r.locality, r.region, r.postal_code, COUNTRY_NAMES["JP"]]
    },

    # ── Qatar: street / area / city / COUNTRY (no postal codes in QA) ─
    "QA" => ->(r) { [r.street_line1, r.street_line2, r.locality, COUNTRY_NAMES["QA"]] },

    # ── Taiwan / Vietnam: street / locality / postal / COUNTRY ────────
    "TW" => ->(r) { [r.street_line1, r.street_line2, r.locality, r.postal_code, COUNTRY_NAMES["TW"]] },
    "VN" => ->(r) { [r.street_line1, r.street_line2, r.locality, r.postal_code, COUNTRY_NAMES["VN"]] },

    # ── South Africa: street / suburb / city / postal / COUNTRY ───────
    # SAPO recommends each element on its own line; postal code last
    # before the country line.
    "ZA" => ->(r) { [r.street_line1, r.street_line2, r.locality, r.postal_code, COUNTRY_NAMES["ZA"]] },

    # ── China: street / locality / postal / COUNTRY ───────────────────
    # International form (smallest-to-largest). Domestic Chinese form
    # would be reverse, but outgoing/incoming international mail uses
    # the order above per UPU S42.
    "CN" => ->(r) { [r.street_line1, r.street_line2, r.locality, r.postal_code, COUNTRY_NAMES["CN"]] }
  }.freeze

  # Generic fallback when we don't have an explicit rule for the country.
  GENERIC_FORMAT = ->(r) {
    city_line = [r.locality, r.region, r.postal_code].compact_blank.join(" ")
    country = COUNTRY_NAMES[r.respond_to?(:mission_country) ? r.mission_country : nil] || r.try(:mission_country).to_s
    [r.street_line1, r.street_line2, city_line, country]
  }

  # ── Shared format helpers ──────────────────────────────────────────
  def self._fr_format(r, country_code)
    city_line = [r.postal_code, r.locality.to_s.upcase].compact_blank.join(" ")
    [r.street_line1, r.street_line2, city_line, COUNTRY_NAMES[country_code]]
  end

  def self._city_comma_postal(r, country_code)
    city_line = if r.postal_code.present? && r.locality.present?
                  "#{r.locality}, #{r.postal_code}"
                else
                  [r.locality, r.postal_code].compact_blank.join(" ")
                end
    [r.street_line1, r.street_line2, city_line, COUNTRY_NAMES[country_code]]
  end

  def self._zip_then_city(r, country_code)
    city_line = [r.postal_code, r.locality].compact_blank.join(" ")
    [r.street_line1, r.street_line2, city_line, COUNTRY_NAMES[country_code]]
  end

  # Italy: "ZIP CITY (PROV)" — province in two-letter code in parens
  def self._italy_format(r)
    city_line = [r.postal_code, r.locality].compact_blank.join(" ")
    city_line = "#{city_line} (#{r.region})" if r.region.present?
    [r.street_line1, r.street_line2, city_line, COUNTRY_NAMES["IT"]]
  end
end
