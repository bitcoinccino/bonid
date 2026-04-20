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
  include HasOperatingHours

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

  # Single source of truth: the Address carries the geographic picker the
  # admin actually fills in. We mirror it onto the office's own scope FKs
  # so the existing scopes (`for_department`, `for_commune`) and the
  # `display_label` keep working without making admins enter the same
  # department/commune twice.
  before_validation :sync_scope_from_address

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

  # Override of HasOperatingHours#display_hours — falls back to the legacy
  # `hours_note` free-text column when no structured slots are set, so any
  # pre-migration row still renders something on the locator.
  def display_hours
    super.presence || hours_note.to_s
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

  # BED → adopts address.department_id. BEK → adopts address.commune_id
  # AND its parent department (commune → arrondissement → department) so the
  # for_department scope still finds it. Skipped if address is missing or the
  # admin hasn't picked the relevant tier yet — geographic_scope_for_office_type
  # will surface the missing-field error.
  def sync_scope_from_address
    return if address.blank?

    case office_type
    when "bed"
      self.department_id = address.department_id if address.department_id.present?
      self.commune_id    = nil
    when "bek"
      if address.commune_id.present?
        self.commune_id    = address.commune_id
        self.department_id = address.commune&.arrondissement&.department_id ||
                             address.department_id
      end
    end
  end
end
