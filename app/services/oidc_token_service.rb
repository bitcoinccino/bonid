# frozen_string_literal: true

class OidcTokenService
  attr_reader :citizen, :scopes

  def initialize(citizen:, scopes:)
    @citizen = citizen
    @scopes  = Array(scopes).map(&:to_s)
  end

  # ------------------------------------------------------------
  # Public interface: returns a hash of allowed attributes
  # ------------------------------------------------------------
  def payload
    return {} unless citizen.present?

    data = { bonid: citizen.bonid }

    if include_scope?("profile")
      data.merge!(
        first_name: citizen.first_name,
        last_name:  citizen.last_name,
        dob:        citizen.dob,
        sex:        citizen.sex,
        nationality: citizen.nationality
      )
    end

    data[:email] = citizen.email if include_scope?("email")
    data[:phone] = citizen.phone if include_scope?("phone")

    # Address is included with either "profile" or "address" scope
    if (include_scope?("profile") || include_scope?("address")) && citizen.respond_to?(:address)
      addr = citizen.address
      data[:address] = {
        street:       addr&.street_address,
        commune:      addr&.commune&.name,
        department:   addr&.department&.name,
        postal_code:  addr&.postal_code,
        country:      "Haiti"
      }.compact
    end

    if include_scope?("physical") && citizen.respond_to?(:physical_profile)
      pp = citizen.physical_profile
      data[:physical] = {
        height_cm:  pp&.height_cm,
        weight_kg:  pp&.weight_kg,
        eye_color:  pp&.eye_color,
        hair_color: pp&.hair_color,
        body_type:  pp&.body_type,
        skin_tone:  pp&.skin_tone
      }.compact
    end

    if include_scope?("health") && citizen.respond_to?(:health_profile)
      hp = citizen.health_profile
      data[:health] = {
        blood_type:         hp&.blood_type,
        allergies:          hp&.allergies_list,
        chronic_conditions: hp&.chronic_conditions_list,
        medications:        hp&.medications_list,
        organ_donor:        hp&.organ_donor
      }.compact
    end

    data.compact
  end

  private

  def include_scope?(key)
    scopes.include?(key.to_s)
  end
end
