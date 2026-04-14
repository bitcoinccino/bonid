# frozen_string_literal: true

# Lightweight voter registry: maps a verified BonID holder to their
# constituency and tracks eligibility + voting status.
#
# ONI manages identity — this model is just the CEP's lookup:
#   "Is this person eligible to vote, and where?"
#
class VoterEligibilityRecord < ApplicationRecord
  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :bonvote_election
  belongs_to :user

  # ============================================================
  # CONSTANTS
  # ============================================================
  STATUSES = %w[eligible ineligible suspended].freeze
  CHANNELS = %w[domestic diaspora].freeze

  INELIGIBILITY_REASONS = {
    "underage"          => "Mwens ke 18 an",
    "no_cin"            => "Pa gen CIN verifye",
    "expired_id"        => "Pyès idantite ekspire",
    "non_haitian"       => "Pa sitwayen ayisyen",
    "suspended"         => "Dwa sivil sispann",
    "duplicate"         => "Deja anrejistre"
  }.freeze

  # ============================================================
  # VALIDATIONS
  # ============================================================
  validates :bonid, presence: true
  validates :department_code, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :channel, inclusion: { in: CHANNELS }, allow_blank: true
  validates :bonid, uniqueness: { scope: :bonvote_election_id, message: "deja anrejistre pou eleksyon sa a" }
  validates :ineligibility_reason, inclusion: { in: INELIGIBILITY_REASONS.keys }, allow_nil: true
  validates :constituency_name, presence: true, if: :eligible?

  # ============================================================
  # SCOPES
  # ============================================================
  scope :eligible,    -> { where(status: "eligible") }
  scope :ineligible,  -> { where(status: "ineligible") }
  scope :voted,       -> { where(has_voted: true) }
  scope :not_voted,   -> { where(has_voted: false) }
  scope :domestic,    -> { where(channel: "domestic") }
  scope :diaspora,    -> { where(channel: "diaspora") }
  scope :for_department, ->(code) { where(department_code: code) }

  # ============================================================
  # CLASS METHODS
  # ============================================================

  # Build voter eligibility from a verified BonID user
  # Returns the record (saved or with errors)
  def self.register_voter!(election:, user:)
    record = find_or_initialize_by(bonvote_election: election, user: user)
    return record if record.persisted? && record.eligible?

    record.assign_attributes(
      bonid: user.bonid,
      cin_number: user.cin_unique_id
    )

    # Determine eligibility
    submission = user.identity_submissions.where(status: :approved).order(created_at: :desc).first

    # Resolve address info upfront
    address = user.address
    local_dept_code = address&.department&.slug || "UNKNOWN"

    if user.bonid.blank?
      record.assign_attributes(status: "ineligible", ineligibility_reason: "no_cin", department_code: local_dept_code)
    elsif submission.blank?
      record.assign_attributes(status: "ineligible", ineligibility_reason: "no_cin", department_code: local_dept_code)
    elsif user.dob.blank? || user.age < 18
      record.assign_attributes(status: "ineligible", ineligibility_reason: "underage", department_code: local_dept_code)
    elsif submission.expires_at.present? && submission.expires_at < Time.current
      record.assign_attributes(status: "ineligible", ineligibility_reason: "expired_id", department_code: local_dept_code)
    else
      # Eligible — determine constituency
      is_diaspora = submission.country_of_residence.present? && submission.country_of_residence != "HT"

      # Domestic: department slug (OU, ND, SE)
      # Diaspora: ISO country code (US, FR, CA) — enables per-country analytics
      dept_code = is_diaspora ? submission.country_of_residence : local_dept_code
      commune_id = address&.commune_id

      # Extract Rekognition face_id and hash it for voter key derivation
      face_id = submission.metadata&.dig("face_collection", "face_id")
      biometric_fp = face_id.present? ? OpenSSL::Digest::SHA256.hexdigest(face_id) : nil

      record.assign_attributes(
        status: "eligible",
        department_code: dept_code,
        commune_id: commune_id,
        channel: is_diaspora ? "diaspora" : "domestic",
        biometric_fingerprint: biometric_fp,
        verified_at: Time.current
      )

      # Set constituency name from election
      constituency = if is_diaspora
        "Dyaspora"
      else
        election.election_constituencies
          .where(position: "deputy", commune_id: commune_id)
          .first&.constituency_name || local_dept_code
      end
      record.constituency_name = constituency
    end

    record.save!
    record
  end

  # Bulk import from all verified BonID users
  def self.build_electoral_list!(election:)
    User.where.not(bonid: [nil, ""])
        .joins(:identity_submissions)
        .where(identity_submissions: { status: :approved })
        .distinct
        .find_each do |user|
      register_voter!(election: election, user: user)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "Voter registration skipped for user #{user.id}: #{e.message}"
    end
  end

  # Lookup: is this BonID eligible for this election?
  def self.check_eligibility(election:, bonid:)
    find_by(bonvote_election: election, bonid: bonid)
  end

  # ============================================================
  # INSTANCE METHODS
  # ============================================================
  def eligible?
    status == "eligible"
  end

  def mark_voted!
    update!(has_voted: true, voted_at: Time.current)
  end

  def ineligibility_label
    INELIGIBILITY_REASONS[ineligibility_reason] || ineligibility_reason
  end

  # Returns the biometric anchor for voter key derivation.
  # Falls back to BonID hash if face_id was not yet enrolled
  # (e.g. pre-Rekognition accounts), ensuring all voters can still vote.
  def biometric_anchor
    biometric_fingerprint.presence || OpenSSL::Digest::SHA256.hexdigest(bonid.to_s)
  end

  # Stats for CEP dashboard
  def self.stats_for(election)
    records = where(bonvote_election: election)
    {
      total_registered: records.count,
      eligible: records.eligible.count,
      ineligible: records.ineligible.count,
      voted: records.voted.count,
      turnout_pct: records.eligible.count.zero? ? 0 : (records.voted.count.to_f / records.eligible.count * 100).round(2),
      domestic: records.domestic.count,
      diaspora: records.diaspora.count
    }
  end
end
