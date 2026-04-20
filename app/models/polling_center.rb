# frozen_string_literal: true

# A physical venue where voting happens — a Sant Vòt.
#
# Domestic centers: Haitian schools, churches, government buildings. Scoped
# by commune + communal section.
#
# Diaspora centers: partner venues abroad (libraries, schools, community
# centers) operating under the jurisdiction of a Haitian diplomatic mission.
# `diplomatic_mission_id` stores the HaitianDiplomaticMissions string key
# (e.g. "HT-CON-MIA") so the supervising consulate is always traceable even
# when the voting itself happens at a neutral third-party site.
#
# A center contains one or more PollingStations (BVs). The system assigns
# voters to individual BVs inside the center, not to the center itself.
class PollingCenter < ApplicationRecord
  include HasOperatingHours

  CENTER_TYPES = %w[domestic diaspora].freeze
  STATUSES     = %w[planned open closed].freeze

  # Building/site kind. Used by partner-admins to plan logistics
  # (a school can absorb 2,000 voters; a town hall typically 400-800).
  # Captured at creation in the wizard, displayed on the index.
  VENUE_TYPES = %w[
    school
    church
    town_hall
    gymnasium
    community_center
    consulate
    embassy
    other
  ].freeze

  VENUE_TYPE_LABELS = {
    "school"           => "Lekòl",
    "church"           => "Legliz",
    "town_hall"        => "Lameri",
    "gymnasium"        => "Jimnaz",
    "community_center" => "Sant Kominote",
    "consulate"        => "Konsila",
    "embassy"          => "Anbasad",
    "other"            => "Lòt"
  }.freeze

  belongs_to :bonvote_election
  belongs_to :partner
  belongs_to :created_by_partner_admin, class_name: "PartnerAdmin", optional: true
  belongs_to :department,       optional: true
  belongs_to :arrondissement,   optional: true
  belongs_to :commune,          optional: true
  belongs_to :communal_section, optional: true

  has_many :polling_stations, dependent: :destroy

  # Authorization scope. CEP (sector="cep") owns election ops globally
  # (see project_admin_vs_cep_boundary memory) and can manage every
  # center; every other partner is restricted to centers their own
  # partner_admins created. URL-tampering on /:id falls through this
  # scope and 404s instead of letting a foreign partner edit a center
  # that doesn't belong to them.
  scope :manageable_by_partner, ->(partner) {
    return none unless partner
    partner.sector.to_s == "cep" ? all : where(partner_id: partner.id)
  }

  # Use the opaque slug in URLs instead of the auto-increment id so no
  # one can enumerate /polling_centers/:n/edit. The integer id stays
  # as the primary key for joins/foreign keys; only the route lookup
  # keys off `slug`.
  before_validation :assign_slug, on: :create
  validates :slug, presence: true, uniqueness: true

  def to_param
    slug
  end

  validates :name, presence: true
  validates :center_type, inclusion: { in: CENTER_TYPES }
  validates :status,      inclusion: { in: STATUSES }
  validates :country_code, presence: true
  validates :venue_type, inclusion: { in: VENUE_TYPES }, allow_blank: true
  validates :expected_capacity, numericality: { only_integer: true,
                                                greater_than: 0 },
                                allow_nil: true

  def venue_type_label
    VENUE_TYPE_LABELS[venue_type] || "—"
  end

  # Domestic centers must be tied to a communal section (finest admin grain).
  # Diaspora centers must carry a diplomatic mission id.
  validates :communal_section_id, presence: true, if: :domestic?
  validates :diplomatic_mission_id, presence: true, if: :diaspora?

  scope :domestic, -> { where(center_type: "domestic") }
  scope :diaspora, -> { where(center_type: "diaspora") }
  scope :active,   -> { where(status: "open") }
  scope :for_section, ->(section_id) { where(communal_section_id: section_id) }
  scope :for_mission, ->(mission_id)  { where(diplomatic_mission_id: mission_id) }

  def domestic?
    center_type == "domestic"
  end

  def diaspora?
    center_type == "diaspora"
  end

  # Total registered voters across every BV in this center.
  def registered_count
    polling_stations.sum(:registered_count)
  end

  # Total seats across every BV in this center.
  def total_capacity
    polling_stations.sum(:capacity)
  end

  # Official Haitian postal display — mirrors Address#formatted_haiti_display
  # exactly so a polling center renders the same way as a citizen's home
  # address. Order:
  #   1. Communal Section
  #   2. Street
  #   3. POSTAL_CODE, COMMUNE (uppercase)
  #   4. HAITI  (or country for diaspora centers)
  def formatted_haiti_display
    return formatted_diaspora_display if diaspora?

    lines = []
    lines << communal_section.name if communal_section&.name.present?
    lines << address_line_1        if address_line_1.present?

    if postal_code.present? && commune&.name.present?
      lines << "#{postal_code.upcase}, #{commune.name.upcase}"
    elsif commune&.name.present?
      lines << commune.name.upcase
    end

    lines << "HAITI"
    lines.join("\n")
  end

  # Single-line variant — joined with commas. Use this where stacking isn't
  # possible (CSV exports, plain-text receipts, SMS).
  def formatted_address
    formatted_haiti_display.split("\n").join(", ")
  end

  private

  # Generated server-side at create — never accepted from input. Uses
  # SecureRandom.uuid (122 bits of entropy) so URL enumeration is
  # computationally infeasible.
  def assign_slug
    return if slug.present?
    self.slug = SecureRandom.uuid
  end

  # Diaspora venues use city + country instead of commune + HAITI.
  def formatted_diaspora_display
    [
      address_line_1,
      address_line_2,
      [ city.presence, state_province.presence ].compact_blank.join(", ").presence,
      [ postal_code, country_code ].compact_blank.join(" ").presence
    ].compact_blank.join("\n")
  end
end
