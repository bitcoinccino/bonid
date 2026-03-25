# frozen_string_literal: true

module BonidGenerator
  extend ActiveSupport::Concern
  require "openssl"
  require "base64"

  # Haiti's 10 departments → 2-letter ISO-style abbreviations.
  # Used in BonID codes: DV-1989-M-SE-P8697XDS
  DEPARTMENT_CODES = {
    "ARTIBONITE" => "AR",
    "CENTRE"     => "CE",
    "GRANDANSE"  => "GA",  # Grand'Anse (apostrophe stripped)
    "NIPPES"     => "NI",
    "NORD"       => "ND",
    "NORDEST"    => "NE",  # Nord-Est (hyphen stripped)
    "NORDOUEST"  => "NO",  # Nord-Ouest (hyphen stripped)
    "OUEST"      => "OU",
    "SUD"        => "SD",
    "SUDEST"     => "SE",  # Sud-Est (hyphen stripped)
  }.freeze

  # --------------------------------------------------------------------------
  # Generates a BonID code from personal identity data.
  # The checksum (last 3 chars) is an HMAC-SHA256 signature fragment,
  # ensuring tamper detection and offline verifiability.
  #
  # Example:
  #   generate_bonid_from_identity!(entity_type: "P")
  #   => "DV-1989-M-SE-P8697XDS"
  # --------------------------------------------------------------------------
  def generate_bonid_from_identity!(entity_type: "P")
    initials  = [ first_name&.first, last_name&.first ].compact.join.upcase.presence || "XX"
    year      = dob&.year.to_s.presence || Time.current.year.to_s
    sex_code  = (sex.presence || "U").to_s[0].upcase
    dept_name = address&.department&.name&.upcase || "HAITI"
    dept_code = department_abbreviation(dept_name)
    id_suffix = id_number.to_s.gsub(/\D/, "")[-4..] || "0000"

    base_code = "#{initials}-#{year}-#{sex_code}-#{dept_code}-#{entity_type}#{id_suffix}"
    checksum  = compute_bonid_checksum(base_code)

    bonid_code = "#{base_code}#{checksum}"
    update_column(:bonid, bonid_code) if respond_to?(:update_column)
    bonid_code
  rescue => e
    Rails.logger.error "❌ BonID generation failed: #{e.message}"
    nil
  end

  # --------------------------------------------------------------------------
  # Verifies that a given BonID string has a valid checksum.
  # Returns true if checksum matches, false otherwise.
  #
  # Example:
  #   verify_bonid_signature("MO-1968-M-OU-P6790H3Z")
  # --------------------------------------------------------------------------
  def verify_bonid_signature(bonid)
    normalized = bonid.to_s.strip.upcase.tr("–—", "-")
    return false if normalized.length < 4

    # Checksum is the last 3 characters (no dash separator)
    checksum  = normalized[-3..]
    base_code = normalized[0..-4]
    expected  = compute_bonid_checksum(base_code).strip.upcase

    ActiveSupport::SecurityUtils.secure_compare(expected, checksum)
  rescue => e
    Rails.logger.error "⚠️ BonID verification failed: #{e.message}"
    false
  end



  private

  # --------------------------------------------------------------------------
  # Converts a department name to its 2-letter abbreviation.
  # Falls back to first 2 letters of the stripped name if not in the map.
  # --------------------------------------------------------------------------
  def department_abbreviation(dept_name)
    stripped = dept_name.to_s.gsub(/[^A-Z]/, "")
    DEPARTMENT_CODES[stripped] || stripped[0..1].presence || "HT"
  end

  # --------------------------------------------------------------------------
  # Internal helper for computing 3-character HMAC checksum.
  # Uses app’s secret key and encodes the digest into a short Base64 fragment.
  # --------------------------------------------------------------------------
  def compute_bonid_checksum(base_code)
    secret = Rails.application.credentials.dig(:bonid, :signature_secret)
    raise "Missing bonid.signature_secret in credentials" if secret.blank?

    digest  = OpenSSL::HMAC.digest("SHA256", secret, base_code)
    base64  = Base64.urlsafe_encode64(digest, padding: false)
    base64[0..2].upcase
  end
end
