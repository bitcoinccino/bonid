# app/models/vehicle.rb
class Vehicle < ApplicationRecord
  include TicketConstants

  # Standard Colors found in PNH/OAVCT records
  OFFICIAL_COLORS = [
    "Blanc", "Noir", "Gris", "Argent", "Rouge",
    "Bleu", "Vert", "Jaune", "Marron", "Or", "Beige", "Orange"
  ].freeze

  # Pillar 5: Evidence & Narrative (Photos of Vehicle/Docs)
  has_one_attached :insurance_card_photo
  has_one_attached :registration_document_photo
  has_many_attached :vehicle_photos

  belongs_to :owner, class_name: "PersonInvolvement", foreign_key: "person_involvement_id"

  enum :verification_status, {
    pending: "En attente",
    verified: "Vérifié",
    rejected: "Rejeté",
    expired: "Expiré"
  }, default: :pending

  # Validations for Haiti Legal Standards
  validates :plate_number, presence: true, uniqueness: true
  validates :vin, presence: true, uniqueness: true # Vehicle Identification Number
  validates :make, :model, presence: true

  # Color Validations
  validates :color, presence: true, inclusion: { in: OFFICIAL_COLORS }
  validates :secondary_color, inclusion: { in: OFFICIAL_COLORS }, allow_blank: true

  validates :oavct_policy_number, presence: true
  validates :oavct_expires_on, presence: true

  # Custom validation: Ensure they upload at least the insurance photo
  validate :must_have_insurance_photo, on: :create

  # Helper for UI display (Officer Dashboard)
  def full_description
    desc = "#{color} #{make} #{model}"
    desc += " (Secondaire: #{secondary_color})" if secondary_color.present?
    desc
  end

  private

  def must_have_insurance_photo
    unless insurance_card_photo.attached?
      errors.add(:insurance_card_photo, "est requis pour la vérification (Vignette OAVCT)")
    end
  end
end
