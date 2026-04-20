# frozen_string_literal: true

# Per-election activation + operating hours for a Haitian diplomatic mission
# (embassy or consulate). Diaspora citizens see this in the locator: which
# consulates are accepting voter registrations or hosting voting for THIS
# election cycle, on what days/hours, with what local contact.
#
# The mission itself is a static record in the HaitianDiplomaticMissions
# concern (a code constant). This table only carries election-scoped state.
# Resolve to the static mission via #mission.
#
# One row per (election, mission). Trying to register the same mission
# twice for the same election is blocked at the unique index.
class ElectionMissionParticipation < ApplicationRecord
  include HasOperatingHours
  include HaitianDiplomaticMissions

  # Lifecycle of a mission's participation in an election:
  #   - inactive           — record exists but mission isn't doing anything yet
  #   - registration_open  — accepting voter registrations (pre-vote window)
  #   - voting_open        — election day / voting window in progress
  #   - closed             — done for this cycle
  STATUSES = %w[inactive registration_open voting_open closed].freeze
  STATUS_LABELS = {
    "inactive"          => "Pa aktif",
    "registration_open" => "Enskripsyon Louvri",
    "voting_open"       => "Vòt Louvri",
    "closed"            => "Fèmen"
  }.freeze

  belongs_to :election, class_name: "BonvoteElection"

  # Opaque slug used in URLs so /diplomatic_missions/:n/edit can't be
  # enumerated by guessing sequential ids. Generated server-side at
  # create — never accepted from input. Mission ids themselves
  # (HT-CON-MIA, HT-CON-ATL, …) are intentionally public; the
  # participation record id is what we hide.
  before_validation :assign_slug, on: :create
  validates :slug, presence: true, uniqueness: true

  def to_param
    slug
  end

  validates :diplomatic_mission_id, presence: true
  validates :diplomatic_mission_id,
            uniqueness: { scope: :election_id, message: "deja konfigire pou eleksyon sa" }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate  :diplomatic_mission_id_must_exist
  validates :contact_email,
            format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  # Address fields are required only once the mission goes "live" — i.e.
  # registration_open or voting_open. Inactive/closed rows can sit with
  # blank addresses (useful while CEP is still gathering data).
  with_options if: :address_required? do
    validates :street_line1, presence: { message: "obligatwa lè misyon an aktif" }
    validates :locality,     presence: { message: "obligatwa lè misyon an aktif" }
  end

  scope :active,             -> { where.not(status: "inactive") }
  scope :registration_open,  -> { where(status: "registration_open") }
  scope :voting_open,        -> { where(status: "voting_open") }
  scope :closed,             -> { where(status: "closed") }
  scope :for_election,       ->(id) { where(election_id: id) }

  # Returns the static mission hash from HaitianDiplomaticMissions
  # (e.g. { id: "HT-CON-MIA", name: "Miami, FL", type: "consulate_general", ... }).
  def mission
    @mission ||= ALL_MISSIONS.find { |m| m[:id] == diplomatic_mission_id }
  end

  def mission_name
    mission&.dig(:name) || diplomatic_mission_id
  end

  def mission_country
    mission&.dig(:country)
  end

  def mission_region
    mission&.dig(:region)
  end

  def mission_type
    mission&.dig(:type)
  end

  def mission_type_label
    MISSION_TYPES[mission_type]
  end

  # Human label combining type + city — "Konsila Jeneral, Miami, FL".
  def display_label
    [mission_type_label, mission_name].compact_blank.join(" — ")
  end

  def status_label
    STATUS_LABELS[status] || status.to_s.titleize
  end

  # UPU S42-formatted postal address as a single string with newline
  # separators. Returns nil when the structured fields are still blank.
  def full_address
    return nil if street_line1.blank? && locality.blank?
    PostalAddressFormatter.new(self).call
  end

  # Same as #full_address but as an Array of lines — useful for views that
  # want to render each line in a separate <div> or <li>.
  def full_address_lines
    return [] if street_line1.blank? && locality.blank?
    PostalAddressFormatter.new(self).as_lines
  end

  def address_required?
    %w[registration_open voting_open].include?(status)
  end

  private

  def diplomatic_mission_id_must_exist
    return if diplomatic_mission_id.blank?
    return if ALL_MISSIONS.any? { |m| m[:id] == diplomatic_mission_id }
    errors.add(:diplomatic_mission_id, "pa egziste nan rejis misyon yo")
  end

  # Generated server-side at create — never accepted from input. Uses
  # SecureRandom.uuid (122 bits of entropy) so URL enumeration is
  # computationally infeasible.
  def assign_slug
    return if slug.present?
    self.slug = SecureRandom.uuid
  end
end
