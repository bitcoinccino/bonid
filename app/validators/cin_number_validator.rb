# frozen_string_literal: true

# Validates Haitian CIN (Carte d'Identification Nationale) numbers
# and passport numbers based on official ONI formats.
#
# CIN Formats (source: ECOI.net / Austrian Red Cross reference):
#   - NINU (2018+):  10 digits — new biometric polycarbonate card
#   - NIN 2nd gen (2014+): 14 digits — XX-XX-XX-XXXX-XX-XX
#   - NIN 1st gen (2005-2014): 17 digits — XX-XX-XX-XXXX-XX-XXXXX
#
# Passport: 6-9 alphanumeric characters
#
class CinNumberValidator
  # New CIN (2018+) — 10-digit NINU (Numéro d'Identification National Unique)
  NINU_FORMAT = /\A\d{10}\z/

  # Old CIN 2nd generation (Dec 2014+) — 14 digits
  NIN_14_FORMAT = /\A\d{14}\z/

  # Old CIN 1st generation (2005–2014) — 17 digits
  NIN_17_FORMAT = /\A\d{17}\z/

  # Haitian passport — alphanumeric, 6–9 characters
  PASSPORT_FORMAT = /\A[A-Z0-9]{6,9}\z/i

  # Validate a document number against the expected format for the given ID type.
  # Strips dashes and spaces before checking.
  def self.valid?(number, id_type)
    return false if number.blank?

    cleaned = normalize(number)

    case id_type.to_s
    when "cin"
      cleaned.match?(NINU_FORMAT) ||
        cleaned.match?(NIN_14_FORMAT) ||
        cleaned.match?(NIN_17_FORMAT)
    when "passport"
      cleaned.match?(PASSPORT_FORMAT)
    else
      true # Other ID types: no format validation yet
    end
  end

  # Returns a human-readable label for the CIN generation.
  def self.format_label(number)
    return "Unknown" if number.blank?

    cleaned = normalize(number)

    case cleaned.length
    when 10 then "NINU (2018+)"
    when 14 then "NIN 2e jenerasyon (2014+)"
    when 17 then "NIN 1e jenerasyon (2005–2014)"
    else "Enkoni"
    end
  end

  # Returns the CIN generation as a symbol for programmatic use.
  def self.generation(number)
    return nil if number.blank?

    cleaned = normalize(number)

    case cleaned.length
    when 10 then :ninu
    when 14 then :nin_2nd_gen
    when 17 then :nin_1st_gen
    else nil
    end
  end

  # Strip dashes, spaces, and dots from the number.
  def self.normalize(number)
    number.to_s.gsub(/[-\s.]/, "")
  end
end
