# frozen_string_literal: true

# Durable audit trail for the election oath (Sèman Vòt) that every
# citizen must acknowledge before casting a ballot. Without this table
# the oath is just a session-scoped checkbox; with it, BonID can
# produce the signed acknowledgment to CEP or a tribunal for any
# disputed vote or fraud prosecution.
#
# One row per (user, election, oath_version). Re-signing the same
# version is a no-op — idempotency via the unique index.
#
# Linked to the `identity_submission` that supplied the rendered
# BonID signature so the evidence chain is: "this human, using this
# approved KYC signature, acknowledged oath version X at time T from
# IP I on user-agent UA."
class CreateVoterOathAcknowledgements < ActiveRecord::Migration[8.0]
  def change
    create_table :voter_oath_acknowledgements do |t|
      t.references :user,                null: false, foreign_key: true
      t.references :bonvote_election,    null: false, foreign_key: true
      t.references :identity_submission, null: true,  foreign_key: true

      t.datetime :accepted_at,  null: false
      t.string   :ip_address,   limit: 45  # IPv6-safe
      t.string   :user_agent,   limit: 512
      t.string   :oath_version, null: false, default: "v1"
      t.string   :digest,       null: false  # SHA256 anti-tamper checksum

      t.timestamps
    end

    add_index :voter_oath_acknowledgements,
              [:user_id, :bonvote_election_id, :oath_version],
              unique: true,
              name: "idx_voter_oath_uniq_per_election"
    add_index :voter_oath_acknowledgements, :accepted_at
    add_index :voter_oath_acknowledgements, :digest, unique: true
  end
end
