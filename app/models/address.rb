# app/models/address.rb
class Address < ApplicationRecord
  belongs_to :addressable, polymorphic: true


 
   # ✅ OPTIONAL: only include these if they are explicitly required and seeded
   belongs_to :communal_section
   belongs_to :commune
   belongs_to :arrondissement
   belongs_to :department
  

  delegate :commune, to: :communal_section, allow_nil: true
  delegate :arrondissement, to: :commune, allow_nil: true
  delegate :department, to: :arrondissement, allow_nil: true

  attr_accessor :department_id, :arrondissement_id, :commune_id

  before_save :set_communal_section_from_ids
  before_save :generate_postal_code
  geocoded_by :to_geocode
  after_validation :geocode, if: ->(obj) { obj.to_geocode.present? && (obj.latitude.blank? || obj.longitude.blank?) }
  


  def to_geocode
    [
      street_address,
      commune&.name || communal_section&.name,
      department&.name,
      country || "Haiti"
    ].compact.join(', ')
  end
  
  
  def formatted_address
    [
      communal_section&.name,                 # 1re Section Pétion-Ville
      street_address || locality,            # Pèlerin 5
      [postal_code, commune&.name].compact.join(", ").upcase, # HT6140, PÉTION-VILLE
      country&.upcase || "HAITI"             # HAITI
    ].compact.join("<br>").html_safe
  end

  private

  def set_communal_section_from_ids
    if communal_section_id.present?
      # Already set by form, no action needed
      return
    elsif commune_id.present?
      # Load the first communal section for the selected commune
      commune = Commune.find_by(id: commune_id)
      self.communal_section = commune&.communal_sections&.first
    elsif arrondissement_id.present?
      # Load the first communal section for the selected arrondissement
      arrondissement = Arrondissement.find_by(id: arrondissement_id)
      first_commune = arrondissement&.communes&.first
      self.communal_section = first_commune&.communal_sections&.first
    elsif department_id.present?
      # Load the first communal section for the selected department
      department = Department.find_by(id: department_id)
      first_arrondissement = department&.arrondissements&.first
      first_commune = first_arrondissement&.communes&.first
      self.communal_section = first_commune&.communal_sections&.first
    end

    # Ensure commune_id is not stored redundantly since it's derived from communal_section
    self.commune_id = nil if communal_section.present?
  end

  def generate_postal_code
    if communal_section&.postal_code.present?
      raw_code = communal_section.postal_code.to_s.gsub(/^HT/, '')
      self.postal_code = "HT#{raw_code.rjust(4, '0')}"
    else
      self.postal_code = "HT0000"
    end
  end
  
end
