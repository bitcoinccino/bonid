# frozen_string_literal: true

# Tracks multi-signature ceremony for election result decryption.
# 5-of-9 quorum required before results can be unlocked.
#
class ElectionSignature < ApplicationRecord
  ROLES = %w[
    cep_president cep_vice_president cep_secretary
    cep_member_1 cep_member_2 cep_member_3
    cep_member_4 cep_member_5 cep_member_6
  ].freeze
  QUORUM = 5

  belongs_to :election, class_name: "BonvoteElection"

  validates :bonid, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :signatory_name, presence: true
  validates :signed_at, presence: true
  validates :role, uniqueness: { scope: :election_id, message: "wòl sa a deja siyen" }
  validates :bonid, uniqueness: { scope: :election_id, message: "moun sa a deja siyen" }

  scope :verified, -> { where(liveness_verified: true) }

  def self.quorum_met?(election_id)
    where(election_id: election_id, liveness_verified: true).count >= QUORUM
  end

  def self.status_for(election_id)
    sigs = where(election_id: election_id)
    signed_roles = sigs.pluck(:role)

    {
      total: sigs.count,
      required: QUORUM,
      met: sigs.where(liveness_verified: true).count >= QUORUM,
      remaining: [QUORUM - sigs.where(liveness_verified: true).count, 0].max,
      signatories: sigs.map { |s| { role: s.role, name: s.signatory_name, verified: s.liveness_verified, signed_at: s.signed_at } },
      available_roles: ROLES - signed_roles
    }
  end

  def self.role_label(role)
    {
      "cep_president"      => "Prezidan CEP",
      "cep_vice_president" => "Vis-Prezidan CEP",
      "cep_secretary"      => "Sekretè Jeneral CEP",
      "cep_member_1"       => "Manm Konseye 1",
      "cep_member_2"       => "Manm Konseye 2",
      "cep_member_3"       => "Manm Konseye 3",
      "cep_member_4"       => "Manm Konseye 4",
      "cep_member_5"       => "Manm Konseye 5",
      "cep_member_6"       => "Manm Konseye 6"
    }[role] || role
  end
end
