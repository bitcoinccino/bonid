# frozen_string_literal: true

# Persists the 9 Shamir Secret Sharing shards generated when a CEP
# election master decryption key is created. 5-of-9 quorum (mirrors
# Election::MultiSigService::QUORUM_REQUIRED). Each row is owned by
# exactly one CEP council role (and one BonID once distributed) and
# carries:
#
#   * `shard_value_encrypted` — what we ship to the council member.
#     v1 stores the raw share string here (placeholder until the
#     BonID-pubkey-encrypted distribution flow lands). NEVER expose
#     this column on a citizen-facing surface.
#   * `shard_hash` — SHA-256 of the cleartext share, captured at
#     generation. On ceremony day we compare the submitted shard's
#     hash against this to detect tampering before ever calling
#     SecretSharing.reconstruct.
#   * Distribution + usage timestamps for full audit.
#
# Unique constraints lock one shard per (election, role) AND one shard
# per (election, BonID), so the same person can't be assigned two
# council seats and a single seat can't be doubly-shared.
class CreateElectionKeyShards < ActiveRecord::Migration[8.0]
  def change
    create_table :election_key_shards do |t|
      t.references :election, null: false,
                              foreign_key: { to_table: :bonvote_elections }
      t.string  :role,                  null: false
      t.string  :bonid                  # NULL until council seat is assigned
      t.text    :shard_value_encrypted, null: false
      t.string  :shard_hash,            null: false
      t.integer :threshold,             null: false, default: 5
      t.integer :total_shards,          null: false, default: 9

      # Distribution audit
      t.string   :distribution_method   # "bonid_encrypted_email" / "envelope" / "qr_only"
      t.string   :distributed_to        # email or BonID actually shipped to
      t.datetime :distributed_at

      # Usage audit (set when this shard is consumed in the ceremony)
      t.datetime :used_at
      t.references :used_in_signature,
                   foreign_key: { to_table: :election_signatures },
                   null: true

      t.timestamps
    end

    add_index :election_key_shards, [ :election_id, :role ],  unique: true,
              name: "idx_key_shards_election_role"
    add_index :election_key_shards, [ :election_id, :bonid ], unique: true,
              where: "bonid IS NOT NULL",
              name: "idx_key_shards_election_bonid"
    add_index :election_key_shards, :shard_hash

    # Master key fingerprint on the election so we can verify a recovered
    # secret matches the originally-generated one before decrypting tally.
    add_column :bonvote_elections, :decryption_key_fingerprint, :string
    add_column :bonvote_elections, :decryption_key_generated_at, :datetime
  end
end
