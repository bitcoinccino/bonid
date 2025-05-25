class Partner < ApplicationRecord
  # belongs_to :partner_application, optional: true
  has_one_attached :logo
  has_many :scan_logs
  has_many :qr_scans, dependent: :nullify
  has_many :partner_applications, dependent: :destroy
  has_one :address, as: :addressable, dependent: :destroy
  accepts_nested_attributes_for :address, update_only: true
  

  delegate :street_address, :communal_section, :commune, :arrondissement, :department, to: :address, allow_nil: true

  geocoded_by :full_address
  after_validation :geocode, if: -> { address.present? && address.changed? }

  def full_address
    return nil unless address

    [
      street_address,
      communal_section&.name,
      commune&.name,
      arrondissement&.name,
      department&.name,
      "Haiti"
    ].compact.join(", ")
  end

  def full_name
    "#{contact_person} – #{name}"
  end

  after_update :auto_create_address, if: -> { verified_at_previously_changed? && verified_at.present? }

  def auto_create_address
    return if address.present? || communal_section_id.blank?

    section = CommunalSection.includes(commune: { arrondissement: :department }).find_by(id: communal_section_id)
    return unless section

    create_address!(
      street_address: street_address.presence || "N/A",
      locality: locality.presence || "N/A",
      postal_code: section.postal_code || "HT0000",
      country: country || "Haiti",
      communal_section: section,
      commune: section.commune,
      arrondissement: section.commune.arrondissement,
      department: section.commune.arrondissement.department
    )
  end
  
end

