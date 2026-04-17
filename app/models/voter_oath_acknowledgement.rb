# frozen_string_literal: true

# Signed oath record — one per (user, election, oath_version).
#
# The citizen reviews the guideline cards on the oath page
# (`app/views/citizens/election/vote/oath.html.erb`), confirms their
# BonID signature, ticks the acceptance checkbox, and submits. That
# POST writes a row here. The row carries:
#
#   - user + election + oath_version → identity of the signer + scope
#   - identity_submission            → which approved BonID signature
#                                       was rendered on the oath page
#   - accepted_at                    → when they clicked
#   - ip_address + user_agent        → device fingerprint for dispute
#   - digest                         → SHA256 anti-tamper checksum
#
# CEP admins can list / search these rows and drill from a specific
# ballot nullifier back to the oath that preceded it. Citizens see
# their own rows in the Aktivite feed.
class VoterOathAcknowledgement < ApplicationRecord
  # Bump when the oath copy changes materially (legal-weight updates,
  # reworded security bullets, new penalty clauses). A version bump
  # forces everyone to re-sign — old `v1` rows stay valid as proof of
  # what was agreed to at the time.
  CURRENT_VERSION = "v1"

  belongs_to :user
  belongs_to :bonvote_election
  belongs_to :identity_submission, optional: true

  validates :accepted_at,  presence: true
  validates :oath_version, presence: true
  validates :digest,       presence: true, uniqueness: true
  validates :user_id, uniqueness: { scope: [:bonvote_election_id, :oath_version] }

  before_validation :ensure_accepted_at, on: :create
  before_validation :compute_digest,     on: :create

  scope :for_election, ->(election) { where(bonvote_election: election) }
  scope :recent_first, -> { order(accepted_at: :desc) }

  # Idempotent signing — returns the existing row if one exists for
  # this (user, election, oath_version), otherwise creates it. This
  # matches the "sign once per election" semantic and protects against
  # double-POSTs from flaky networks.
  def self.sign!(user:, bonvote_election:, identity_submission: nil, ip_address: nil, user_agent: nil, oath_version: CURRENT_VERSION)
    existing = find_by(user: user, bonvote_election: bonvote_election, oath_version: oath_version)
    return existing if existing

    create!(
      user: user,
      bonvote_election: bonvote_election,
      identity_submission: identity_submission,
      accepted_at: Time.current,
      ip_address: ip_address.to_s.presence,
      user_agent: user_agent.to_s.presence&.first(500),
      oath_version: oath_version
    )
  end

  def self.signed?(user:, bonvote_election:, oath_version: CURRENT_VERSION)
    exists?(user: user, bonvote_election: bonvote_election, oath_version: oath_version)
  end

  # Re-compute the digest from the persisted fields and compare to the
  # stored value. Used by CEP auditors to detect tampering at the
  # database layer (someone editing `accepted_at` directly, for
  # example, would invalidate the digest).
  def tamper_free?
    digest == OpenSSL::Digest::SHA256.hexdigest(digest_payload)
  end

  private

  def ensure_accepted_at
    self.accepted_at ||= Time.current
  end

  def compute_digest
    self.digest ||= OpenSSL::Digest::SHA256.hexdigest(digest_payload)
  end

  def digest_payload
    [user_id, bonvote_election_id, accepted_at.to_i, oath_version].join(":")
  end
end
