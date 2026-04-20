# frozen_string_literal: true

# Bureau du Contentieux Electoral National (BCEN) — Haiti's highest
# instance for disputes over electoral matters.
#
# OAS Report: "The CIEVE reviewed 143 complaints. The BCEN analyzed
# 78 randomly selected electoral returns... 26 were eliminated from
# the final count."
#
# The OAS recommends establishing a permanent, independent electoral
# dispute authority with trained attorneys specializing in electoral law.
#
class ElectionDispute < ApplicationRecord
  DISPUTE_TYPES = %w[complaint challenge annulment_request recount_request fraud_report].freeze
  FILER_TYPES   = %w[candidate party observer citizen].freeze
  STATUSES      = %w[filed under_review hearing_scheduled decided appealed closed].freeze
  DECISION_TYPES = %w[upheld dismissed partial referred].freeze

  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :constituency, class_name: "ElectionConstituency", optional: true
  belongs_to :election_body, optional: true
  # Set when the dispute challenges a specific candidate on the liste
  # préliminaire (Article 192 contestation de candidature).
  belongs_to :election_candidate, optional: true

  validates :dispute_type, presence: true, inclusion: { in: DISPUTE_TYPES }
  validates :reference_code, presence: true, uniqueness: { scope: :election_id }
  validates :filed_by_type, presence: true, inclusion: { in: FILER_TYPES }
  validates :filed_by_name, presence: true
  validates :subject, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :decision_type, inclusion: { in: DECISION_TYPES }, allow_nil: true

  scope :open,      -> { where(status: %w[filed under_review hearing_scheduled]) }
  scope :decided,   -> { where(status: "decided") }
  scope :urgent,    -> { where(priority: "urgent") }
  scope :for_department, ->(code) { where(department_code: code) }

  before_validation :generate_reference_code, on: :create
  before_validation :set_filed_at, on: :create

  def open?    = %w[filed under_review hearing_scheduled].include?(status)
  def decided? = status == "decided"

  # Move through workflow
  def start_review!(officer_name:, officer_bonid: nil)
    update!(status: "under_review", assigned_to: officer_name, assigned_to_bonid: officer_bonid)
  end

  def schedule_hearing!(hearing_date:)
    update!(status: "hearing_scheduled", hearing_at: hearing_date)
  end

  def decide!(decision_text:, decision_type:)
    update!(
      status: "decided",
      decision: decision_text,
      decision_type: decision_type,
      decided_at: Time.current,
      appeal_deadline: Time.current + 5.days # Standard appeal window
    )
  end

  def close!
    update!(status: "closed")
  end

  # Stats for BCEN dashboard
  def self.stats_for(election_id)
    disputes = where(election_id: election_id)
    {
      total: disputes.count,
      open: disputes.open.count,
      decided: disputes.decided.count,
      by_type: disputes.group(:dispute_type).count,
      by_status: disputes.group(:status).count,
      by_department: disputes.group(:department_code).count,
      urgent: disputes.urgent.count
    }
  end

  private

  def generate_reference_code
    return if reference_code.present?

    year = election&.election_date&.year || Date.current.year
    random = SecureRandom.hex(4).upcase
    self.reference_code = "BCEN-#{year}-#{random}"
  end

  def set_filed_at
    self.filed_at ||= Time.current
  end
end
