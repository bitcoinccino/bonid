# frozen_string_literal: true

# Step 2 of the CEP decryption ceremony: shard distribution by sealed
# X25519 envelope.
#
# Before this migration: `shard_value_encrypted` held the cleartext
# Shamir share (placeholder, called out in the original migration).
# After this migration: it holds an X25519+AES-256-GCM wire string
# (see Election::ShardEnvelope) and the per-shard recipient public key
# is captured alongside for audit / re-seal scenarios.
#
# `recipient_public_key_b64` is the X25519 public half. The matching
# private half is printed onto the council member's envelope at
# generation time and is NEVER stored server-side.
class AddEnvelopeToElectionKeyShards < ActiveRecord::Migration[8.0]
  def change
    add_column :election_key_shards, :envelope_version,         :string, default: "v1"
    add_column :election_key_shards, :recipient_public_key_b64, :text
  end
end
