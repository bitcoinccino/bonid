# frozen_string_literal: true

# One Shamir share of an election's master decryption key. Generated in
# bulk (9 shards per election) by Election::DecryptionKeyCeremonyService
# at the moment the election is locked, then distributed to the 9 CEP
# council members. On ceremony day, 5 valid shards reconstruct the
# master key (see Election::MultiSigService#trigger_final_tally).
#
# Security notes:
#   * `shard_value_encrypted` and `shard_hash` together are the
#     entirety of what an attacker would need to forge participation —
#     never expose this model on a citizen surface, never serialize the
#     value in logs, and never include it in `attributes` payloads.
#   * `bonid` is nullable until a council seat is assigned; the unique
#     index on (election_id, bonid) is partial so we don't trip when
#     several shards are still un-assigned during initial generation.
class ElectionKeyShard < ApplicationRecord
  ROLES  = ElectionSignature::ROLES.freeze
  QUORUM = ElectionSignature::QUORUM

  belongs_to :election, class_name: "BonvoteElection"
  belongs_to :used_in_signature, class_name: "ElectionSignature", optional: true

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :role, uniqueness: { scope: :election_id }
  validates :bonid, uniqueness: { scope: :election_id, allow_nil: true }
  validates :shard_value_encrypted, presence: true
  validates :shard_hash, presence: true,
                        format: { with: /\A[0-9a-f]{64}\z/, message: "dwe yon SHA-256 hex" }
  validates :threshold,    numericality: { greater_than: 0 }
  validates :total_shards, numericality: { greater_than_or_equal_to: :threshold }

  scope :distributed,    -> { where.not(distributed_at: nil) }
  scope :pending,        -> { where(distributed_at: nil) }
  scope :unused,         -> { where(used_at: nil) }

  def role_label
    ElectionSignature.role_label(role)
  end

  # True iff `shard_value` (the cleartext share) round-trips through the
  # SHA-256 we captured at generation time. Use this to detect tampering
  # of distributed envelopes / emails before reconstructing the master.
  def matches?(shard_value)
    return false if shard_value.blank? || shard_hash.blank?
    OpenSSL::Digest::SHA256.hexdigest(shard_value.to_s) == shard_hash
  end

  # Mark this shard as consumed in the ceremony. Records the linked
  # ElectionSignature so audit can trace shard → signer → tally trigger.
  def mark_used!(signature: nil)
    update!(used_at: Time.current, used_in_signature: signature)
  end
end
