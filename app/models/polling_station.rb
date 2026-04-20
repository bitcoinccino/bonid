# frozen_string_literal: true

# A single voting table (Biwo Vòt / BV) inside a PollingCenter.
#
# Capacity defaults to 450 voters per BV per Haitian LEEC 2015 standards.
# `registered_count` is incremented atomically during voter assignment —
# Phase 2 will wire the `FOR UPDATE SKIP LOCKED` block into
# VoterEligibilityRecord.register_voter! to prevent over-filling.
class PollingStation < ApplicationRecord
  STATUSES = %w[open full closed].freeze

  belongs_to :polling_center
  has_many   :voter_eligibility_records, dependent: :restrict_with_error

  # Opaque slug used in URLs so /polling_stations/:n/edit can't be
  # enumerated by guessing sequential ids. Generated server-side at
  # create — never accepted from input.
  before_validation :assign_slug, on: :create
  validates :slug, presence: true, uniqueness: true

  def to_param
    slug
  end

  validates :bv_number, presence: true,
                        numericality: { greater_than: 0, only_integer: true },
                        uniqueness: { scope: :polling_center_id }
  validates :capacity, numericality: { greater_than: 0, only_integer: true }
  validates :registered_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :status, inclusion: { in: STATUSES }

  scope :open,       -> { where(status: "open") }
  # CEP-only. Never expose the records returned by this scope (or their
  # `capacity` / `registered_count`) to citizens or partner staff. Those
  # columns leak per-station demographic throughput: an attacker who knows
  # `registered_count` per BV can infer turnout and neighborhood composition
  # station by station. The assigner consumes this scope server-side and
  # only surfaces `bv_number` + `polling_center.name` to the citizen.
  scope :available,  -> { open.where("registered_count < capacity") }
  scope :ordered,    -> { joins(:polling_center).order("polling_centers.priority ASC, polling_stations.bv_number ASC") }

  # Helpers the Phase 2 assigner will rely on.
  def full?
    registered_count >= capacity
  end

  def available?
    status == "open" && !full?
  end

  # Deterministic label: "BV #14 — Lycée Saint-Louis de Gonzague"
  def display_label
    "BV ##{bv_number} — #{polling_center&.name}"
  end

  private

  def assign_slug
    return if slug.present?
    self.slug = SecureRandom.uuid
  end
end
