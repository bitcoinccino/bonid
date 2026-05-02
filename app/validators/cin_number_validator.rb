# frozen_string_literal: true

# Validates Haitian CIN (Carte d'Identification Nationale) numbers
# and passport numbers based on official ONI formats.
#
# As of January 2026 the ONI mandates the 10-digit NINU (Numéro
# d'Identification National Unique) for all passport applications,
# renewals, and identification flows. Older 14- and 17-digit CINs are
# no longer accepted — citizens still holding them must request a NINU
# from ONI before submitting through BonID.
#
# Passport: 6-9 alphanumeric characters
#
class CinNumberValidator
  # NINU — 10-digit Numéro d'Identification National Unique (ONI 2018+).
  NINU_FORMAT = /\A\d{10}\z/

  # Haitian passport — alphanumeric, 6–9 characters
  PASSPORT_FORMAT = /\A[A-Z0-9]{6,9}\z/i

  # Validate a document number against the expected format for the given ID type.
  # Strips dashes and spaces before checking.
  def self.valid?(number, id_type)
    return false if number.blank?

    cleaned = normalize(number)

    case id_type.to_s
    when "cin"
      cleaned.match?(NINU_FORMAT)
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
    cleaned.length == 10 ? "NINU (10 chif)" : "Enkoni"
  end

  # Returns the CIN generation as a symbol for programmatic use.
  def self.generation(number)
    return nil if number.blank?
    cleaned = normalize(number)
    cleaned.length == 10 ? :ninu : nil
  end

  # Strip dashes, spaces, and dots from the number.
  def self.normalize(number)
    number.to_s.gsub(/[-\s.]/, "")
  end
end
