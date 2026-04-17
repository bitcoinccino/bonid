# frozen_string_literal: true

# CEP's permanent field offices where citizens can walk in for help with
# voter registration, document drop-off, dispute resolution, or anything
# else that needs a human clerk.
#
# Two tiers, mirroring CEP's own administrative structure:
#
#   - BED (Bureau Électoral Départemental) — department-level office.
#     Haiti has 10 departments; Ouest and Grande-Anse have two BEDs
#     each for logistics, so 12 BEDs total.
#
#   - BEK (Bureau Électoral Communal) — commune-level office.
#     One per commune (~140 nationwide).
#
# Distinct from `PollingCenter` (Sant Vòt — election-day voting venues)
# and from `Partner` (third-party institutions like banks or consulates).
# An electoral office is CEP's own infrastructure, permanent across
# electoral cycles.
#
# Addresses reuse the polymorphic `Address` model, which already handles
# the Haitian geographic hierarchy, postal codes, and geocoding.
class ElectoralOffice < ApplicationRecord
  OFFICE_TYPES = %w[bed bek].freeze
  STATUSES     = %w[planned open closed].freeze

  # ── Associations ─────────────────────────────────────────────────
  belongs_to :department, optional: true
  belongs_to :commune,    optional: true

  has_one :address, as: :addressable, dependent: :destroy, inverse_of: :addressable
  accepts_nested_attributes_for :address, update_only: true

  has_many :voter_eligibility_records,
           foreign_key: :registered_by_electoral_office_id,
           dependent: :nullify

  # ── Validations ──────────────────────────────────────────────────
  validates :name,        presence: true
  validates :office_type, presence: true, inclusion: { in: OFFICE_TYPES }
  validates :status,      presence: true, inclusion: { in: STATUSES }

  validate :geographic_scope_for_office_type

  # ── Scopes ───────────────────────────────────────────────────────
  scope :open,      -> { where(status: "open") }
  scope :planned,   -> { where(status: "planned") }
  scope :bed,       -> { where(office_type: "bed") }
  scope :bek,       -> { where(office_type: "bek") }
  scope :for_department, ->(id) { where(department_id: id) }
  scope :for_commune,    ->(id) { where(commune_id: id) }
  scope :ordered,   -> { order(:priority, :name) }

  # ── Helpers ──────────────────────────────────────────────────────
  def bed?
    office_type == "bed"
  end

  def bek?
    office_type == "bek"
  end

  # Human-facing label for dropdowns, locator cards, and admin tables.
  # "BED — Département du Sud-Est" / "BEK — Commune de Pétion-Ville".
  def display_label
    scope_name = bed? ? department&.name : commune&.name
    "#{office_type.upcase} — #{name}#{" — #{scope_name}" if scope_name.present?}"
  end

  # Resolves the department context even for BEKs, which only carry a
  # commune_id directly. Used by the citizen-facing locator.
  def effective_department
    department || commune&.arrondissement&.department
  end

  private

  # BEDs must be scoped to a department; BEKs must be scoped to a commune.
  # (A BEK's department is inferred through commune → arrondissement.)
  # Soft validation — the migration keeps FK columns nullable so a draft
  # record can be saved in the admin form before the geographic picker
  # cascade completes.
  def geographic_scope_for_office_type
    case office_type
    when "bed"
      errors.add(:department_id, "required for a BED") if department_id.blank?
    when "bek"
      errors.add(:commune_id, "required for a BEK") if commune_id.blank?
    end
  end
end
