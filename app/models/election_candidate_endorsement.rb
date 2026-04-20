# frozen_string_literal: true

# A single endorsement toward an independent candidate's Article 181.15
# 2% support petition. Two sources:
#   - "digital" — a verified citizen endorsed through BonID (has `bonid`).
#   - "csv"     — CEP admin uploaded a paper petition row (may have only
#                 `cin_number` and a scanned signature image).
#
# Only `voter_roll_verified: true` rows count toward the 2% threshold — a
# digital endorsement is auto-verified (we confirmed eligibility at click
# time); a CSV row becomes verified only after the admin's import job
# matches the CIN against the voter roll.
class ElectionCandidateEndorsement < ApplicationRecord
  SOURCES = %w[digital csv].freeze

  belongs_to :election_candidate
  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :uploaded_by, class_name: "AdminUser", optional: true

  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :bonid, presence: true, if: -> { source == "digital" }
  validates :endorsed_at, presence: true
  validate  :bonid_or_cin_required

  before_validation :default_timestamp, on: :create

  scope :verified, -> { where(voter_roll_verified: true) }
  scope :digital,  -> { where(source: "digital") }
  scope :csv,      -> { where(source: "csv") }

  # How many verified endorsements a candidate has — this is what counts
  # toward the 2% threshold.
  def self.verified_count_for(candidate)
    where(election_candidate_id: candidate.id).verified.count
  end

  private

  def default_timestamp
    self.endorsed_at ||= Time.current
  end

  def bonid_or_cin_required
    return if bonid.present? || cin_number.present?
    errors.add(:base, "BonID oswa CIN obligatwa")
  end
end
