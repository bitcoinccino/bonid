# frozen_string_literal: true

# Validates Haitian CIN (Carte d'Identification Nationale) numbers
# and passport numbers.
#
# CIN: either the number printed on the CIN card (9 letters/digits,
# e.g. T1K2N8697 — the format the profile form shows as its example) or
# the 10-digit NINU (Numéro d'Identification National Unique).
#
# Passport: 6-9 alphanumeric characters
#
class CinNumberValidator
  # NINU — 10-digit Numéro d'Identification National Unique.
  NINU_FORMAT = /\A\d{10}\z/

  # Number printed on the CIN card — 9 letters/digits (e.g. T1K2N8697).
  CIN_CARD_FORMAT = /\A[A-Z0-9]{9}\z/i

  # Haitian passport — alphanumeric, 6–9 characters
  PASSPORT_FORMAT = /\A[A-Z0-9]{6,9}\z/i

  CIN_ERROR = "Nimewo CIN pa valid. Antre nimewo ki sou kat CIN ou (egz. T1K2N8697) oswa NINU 10 chif ou."

  # Validate a document number against the expected format for the given ID type.
  # Strips dashes and spaces before checking.
  def self.valid?(number, id_type)
    return false if number.blank?

    cleaned = normalize(number)

    case id_type.to_s
    when "cin"
      cleaned.match?(NINU_FORMAT) || cleaned.match?(CIN_CARD_FORMAT)
    when "passport"
      # Passports are now registered with the holder's NINU (DIE requires it);
      # older records carry the passport's own number.
      cleaned.match?(NINU_FORMAT) || cleaned.match?(PASSPORT_FORMAT)
    else
      true # Other ID types: no format validation yet
    end
  end

  # Returns a human-readable label for the CIN generation.
  def self.format_label(number)
    case generation(number)
    when :ninu then "NINU (10 chif)"
    when :cin_card then "Kat CIN (9 karaktè)"
    else number.blank? ? "Unknown" : "Enkoni"
    end
  end

  # Returns the CIN generation as a symbol for programmatic use.
  def self.generation(number)
    return nil if number.blank?

    cleaned = normalize(number)
    return :ninu if cleaned.match?(NINU_FORMAT)
    return :cin_card if cleaned.match?(CIN_CARD_FORMAT)

    nil
  end

  # Strip dashes, spaces, and dots from the number.
  def self.normalize(number)
    number.to_s.gsub(/[-\s.]/, "")
  end
end
