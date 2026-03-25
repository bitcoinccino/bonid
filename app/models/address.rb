# == Schema Information
#
# Table name: addresses
#
# Polymorphic address model used across BonID entities:
# - Citizens, Officers, Partner Admins, Institutions (Hospitals, Banks, Embassies)
# - Incident Reports
#
# Handles Haitian hierarchy (Department → Arrondissement → Commune → Section),
# geocoding, postal code normalization, and Open Location Plus Codes.
#

require "open_location_code"

class Address < ApplicationRecord
  # === Associations ===
  belongs_to :addressable, polymorphic: true, inverse_of: :address
  belongs_to :person_involvement, optional: true
  belongs_to :department, optional: true
  belongs_to :arrondissement, optional: true
  belongs_to :commune, optional: true
  belongs_to :communal_section, optional: true

  # === Delegations ===
  delegate :commune, to: :communal_section, allow_nil: true
  delegate :arrondissement, to: :commune, allow_nil: true
  delegate :department, to: :arrondissement, allow_nil: true

  # === Validations ===
  validates :country, presence: true
  validates :communal_section_id, presence: true, if: -> { country == "Haiti" }
  validates :street_address, presence: true, if: -> { requires_street_address? }

  # === Geocoding ===
  geocoded_by :to_geocode
  reverse_geocoded_by :latitude, :longitude

  # ONLY run geocoding in production — completely disables it in dev/test
  # This eliminates "unknown stub request" and any API calls during development
  after_validation :geocode, if: -> { geocoding_needed? && Rails.env.production? }
  after_validation :reverse_geocode, if: -> { (latitude_changed? || longitude_changed?) && Rails.env.production? }

  # === Callbacks ===
  before_validation :sync_inverse_addressable
  before_validation :ensure_section_hierarchy
  before_save :generate_postal_code
  before_save :normalize_postal_code
  before_save :generate_plus_code, if: -> { latitude.present? && longitude.present? && plus_code.blank? }

  # === Instance Methods ===
  def to_geocode
    [ street_address, commune&.name || communal_section&.name, department&.name, country ].compact.join(", ")
  end

  def formatted_address
    [ street_address || locality, communal_section&.name, commune&.name,
     department&.name, postal_code, country ].compact_blank.join(", ")
  end

  def full_address
    [ street_address, locality, commune&.name, arrondissement&.name,
     department&.name, postal_code, country ].compact_blank.join(", ")
  end
  alias full_formatted full_address

  def city_label
    commune&.name || arrondissement&.name || department&.name || "Unknown"
  end

  def full_label
    full_address.to_s.squish
  end

  def requires_street_address?
    addressable_type == "IncidentReport" && addressable&.persisted?
  end

  def geocoding_needed?
    to_geocode.present? && (latitude.blank? || longitude.blank?)
  end

# ------------------------------------------------------------
# OFFICIAL HAITI DISPLAY FORMAT (BonID / BonTouris)
# ------------------------------------------------------------
def formatted_haiti_display
  return full_address unless country.to_s.casecmp("haiti").zero?

  lines = []

  # Line 1 — Communal Section (as stored, already seeded correctly)
  if communal_section&.name.present?
    lines << communal_section.name
  end

  # Line 2 — Street
  if street_address.present?
    lines << street_address
  end

  # Line 3 — Postal Code + Commune (COMMUNE MUST BE UPPERCASE)
  if postal_code.present? && commune&.name.present?
    lines << "#{postal_code.upcase}, #{commune.name.upcase}"
  end

  # Line 4 — Country (ALWAYS HAITI)
  lines << "HAITI"

  lines.join("\n")
end


  private

  def ensure_section_hierarchy
    return if communal_section_id.present?

    if commune_id.present?
      commune = Commune.includes(:communal_sections).find_by(id: commune_id)
      self.communal_section ||= commune&.communal_sections&.first
    elsif arrondissement_id.present?
      arr = Arrondissement.includes(communes: :communal_sections).find_by(id: arrondissement_id)
      first_commune = arr&.communes&.first
      self.commune_id ||= first_commune&.id
      self.communal_section ||= first_commune&.communal_sections&.first
    elsif department_id.present?
      dept = Department.includes(arrondissements: { communes: :communal_sections }).find_by(id: department_id)
      arr = dept&.arrondissements&.first
      com = arr&.communes&.first
      self.arrondissement_id ||= arr&.id
      self.commune_id ||= com&.id
      self.communal_section ||= com&.communal_sections&.first
    elsif country == "Haiti"
      section = CommunalSection.includes(commune: { arrondissement: :department }).first
      return unless section
      self.communal_section_id ||= section.id
      self.commune_id ||= section.commune_id
      self.arrondissement_id ||= section.commune.arrondissement_id
      self.department_id ||= section.commune.arrondissement.department_id
    end
  end

  def generate_postal_code
    if communal_section&.postal_code.present?
      raw = communal_section.postal_code.to_s.delete_prefix("HT").rjust(4, "0")
      self.postal_code = "HT#{raw}"
    elsif country == "Haiti"
      self.postal_code ||= "HT0000"
    end
  end

  def normalize_postal_code
    self.postal_code = postal_code&.upcase
  end

  def generate_plus_code
    self.plus_code = OpenLocationCode.encode(latitude, longitude)
  rescue StandardError => e
    Rails.logger.warn("Failed to generate Plus Code: #{e.message}")
  end

  def sync_inverse_addressable
    return unless addressable.present?
    return if addressable.new_record? # prevent circular linking on nested create

    self.addressable_type = addressable.class.base_class.name
    self.addressable_id   = addressable.id
  end
end

# Legacy Address# app/models/address.rb
# class Address < ApplicationRecord
#   belongs_to :addressable, polymorphic: true



#    # ✅ OPTIONAL: only include these if they are explicitly required and seeded
#    belongs_to :communal_section
#    belongs_to :commune
#    belongs_to :arrondissement
#    belongs_to :department


#   delegate :commune, to: :communal_section, allow_nil: true
#   delegate :arrondissement, to: :commune, allow_nil: true
#   delegate :department, to: :arrondissement, allow_nil: true

#   attr_accessor :department_id, :arrondissement_id, :commune_id

#   before_save :set_communal_section_from_ids
#   before_save :generate_postal_code
#   geocoded_by :to_geocode
#   after_validation :geocode, if: ->(obj) { obj.to_geocode.present? && (obj.latitude.blank? || obj.longitude.blank?) }



#   def to_geocode
#     [
#       street_address,
#       commune&.name || communal_section&.name,
#       department&.name,
#       country || "Haiti"
#     ].compact.join(', ')
#   end


#   def formatted_address
#     [
#       communal_section&.name,                 # 1re Section Pétion-Ville
#       street_address || locality,            # Pèlerin 5
#       [postal_code, commune&.name].compact.join(", ").upcase, # HT6140, PÉTION-VILLE
#       country&.upcase || "HAITI"             # HAITI
#     ].compact.join("<br>").html_safe
#   end

#   private

#   def set_communal_section_from_ids
#     if communal_section_id.present?
#       # Already set by form, no action needed
#       return
#     elsif commune_id.present?
#       # Load the first communal section for the selected commune
#       commune = Commune.find_by(id: commune_id)
#       self.communal_section = commune&.communal_sections&.first
#     elsif arrondissement_id.present?
#       # Load the first communal section for the selected arrondissement
#       arrondissement = Arrondissement.find_by(id: arrondissement_id)
#       first_commune = arrondissement&.communes&.first
#       self.communal_section = first_commune&.communal_sections&.first
#     elsif department_id.present?
#       # Load the first communal section for the selected department
#       department = Department.find_by(id: department_id)
#       first_arrondissement = department&.arrondissements&.first
#       first_commune = first_arrondissement&.communes&.first
#       self.communal_section = first_commune&.communal_sections&.first
#     end

#     # Ensure commune_id is not stored redundantly since it's derived from communal_section
#     self.commune_id = nil if communal_section.present?
#   end

#   def generate_postal_code
#     if communal_section&.postal_code.present?
#       raw_code = communal_section.postal_code.to_s.gsub(/^HT/, '')
#       self.postal_code = "HT#{raw_code.rjust(4, '0')}"
#     else
#       self.postal_code = "HT0000"
#     end
#   end

# end
