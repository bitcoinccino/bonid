# frozen_string_literal: true

# Promotes the per-election BonVote signing public key from a credential
# blob into a first-class column so:
#
#   1. It can be served at /api/v1/elections/:id/bonvote_public_key for
#      offline verifiers (CEP tablets, third-party auditors, citizens).
#   2. Key rotation is auditable: every active key carries a key_id,
#      and prior keys live in `metadata["bonvote_archived_keys"]` so old
#      receipts stay verifiable after a rotation.
#
# `cep_public_key` was the legacy name (renamed elsewhere in the
# CEP-→BonVote cleanup). Renaming + adding key_id in one migration so the
# schema reflects the new naming consistently.
class AddBonvoteKeyColumnsToElections < ActiveRecord::Migration[8.0]
  def change
    rename_column :bonvote_elections, :cep_public_key, :bonvote_public_key
    add_column    :bonvote_elections, :bonvote_key_id, :string
  end
end
