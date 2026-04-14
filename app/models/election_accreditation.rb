# frozen_string_literal: true

# Personal, non-transferable accreditation for party representatives
# (mandataires) and electoral observers.
#
# OAS Recommendation: "Issue a personal accreditation pass to each political
# representative that shows his full name, national identification (CIN) number,
# photograph, and the polling station where he is registered."
#
# In 2015, the CEP distributed 900,000+ non-personalized accreditation passes.
# This allowed party reps to vote at any station, enabling fraud.
# BonVote fixes this: each accreditation is tied to a BonID + assigned station.
#
class ElectionAccreditation < ApplicationRecord
  TYPES = %w[mandataire national_observer international_observer].freeze

  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :user, optional: true
  belongs_to :assigned_body, class_name: "ElectionBody", optional: true

  validates :accreditation_type, presence: true, inclusion: { in: TYPES }
  validates :full_name, presence: true
  validates :organization, presence: true
  validates :accreditation_code, presence: true, uniqueness: { scope: :election_id }
  validates :bonid, uniqueness: { scope: :election_id, allow_blank: true }
  validates :status, inclusion: { in: %w[pending active suspended revoked] }

  scope :mandataires, -> { where(accreditation_type: "mandataire") }
  scope :observers,   -> { where(accreditation_type: %w[national_observer international_observer]) }
  scope :active,      -> { where(status: "active") }
  scope :verified,    -> { where(identity_verified: true) }
  scope :for_department, ->(code) { where(department_code: code) }

  before_validation :generate_accreditation_code, on: :create

  def mandataire?            = accreditation_type == "mandataire"
  def national_observer?     = accreditation_type == "national_observer"
  def international_observer? = accreditation_type == "international_observer"

  def active?   = status == "active"
  def revoked?  = status == "revoked"

  # Activate after BonID verification
  def activate!
    update!(status: "active", identity_verified: true, issued_at: Time.current)
  end

  # Revoke accreditation (with reason logged)
  def revoke!(reason:, by: nil)
    update!(
      status: "revoked",
      revoked_at: Time.current,
      revocation_reason: reason
    )
  end

  # Type label (Kreyòl)
  def type_label
    { "mandataire" => "Mandatè Pati Politik",
      "national_observer" => "Obsèvatè Nasyonal",
      "international_observer" => "Obsèvatè Entènasyonal" }[accreditation_type]
  end

  private

  def generate_accreditation_code
    return if accreditation_code.present?

    prefix = case accreditation_type
             when "mandataire" then "MAN"
             when "national_observer" then "OBS-N"
             when "international_observer" then "OBS-I"
             else "ACC"
             end
    self.accreditation_code = "#{prefix}-#{SecureRandom.hex(4).upcase}"
  end
end
