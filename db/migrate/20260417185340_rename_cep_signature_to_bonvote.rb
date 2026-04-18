# frozen_string_literal: true

# Renames cep_signature / cep_signed_at → bonvote_signature / bonvote_signed_at.
#
# The signature is produced by a BonVote-held private key; the previous column
# name implied CEP authorship. BonVote follows CEP's protocol — it does not
# sign on CEP's behalf. The honest attestation is: "BonVote issued this
# receipt according to CEP's protocol." The badge on the receipt now reads
# "Siyen pa BonVote · Pwotokòl CEP", and the columns back that label.
class RenameCepSignatureToBonvote < ActiveRecord::Migration[8.0]
  def change
    rename_column :voter_eligibility_records, :cep_signature, :bonvote_signature
    rename_column :voter_eligibility_records, :cep_signed_at, :bonvote_signed_at
  end
end
