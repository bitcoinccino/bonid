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
  CENTER_TYPES = %w[domestic diaspora].freeze
  STATUSES     = %w[planned open closed].freeze

  belongs_to :bonvote_election
  belongs_to :department,       optional: true
  belongs_to :arrondissement,   optional: true
  belongs_to :commune,          optional: true
  belongs_to :communal_section, optional: true

  has_many :polling_stations, dependent: :destroy

  validates :name, presence: true
  validates :center_type, inclusion: { in: CENTER_TYPES }
  validates :status,      inclusion: { in: STATUSES }
  validates :country_code, presence: true

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

  # Human-friendly single-line address for voter cards / UI.
  #
  # Falls back to the Haitian admin hierarchy (department / commune / section)
  # when the free-text columns are blank — so a polling center seeded with
  # only FKs still renders a useful address instead of just "HT".
  def formatted_address
    [
      address_line_1,
      address_line_2.presence || communal_section&.name,
      city.presence           || commune&.name,
      state_province.presence || department&.name,
      postal_code,
      country_code
    ].compact_blank.join(", ")
  end
end
