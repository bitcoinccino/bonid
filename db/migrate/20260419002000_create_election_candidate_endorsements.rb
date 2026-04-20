# frozen_string_literal: true

# Article 181.15 of the Décret Électoral (1er Décembre 2025):
# independent candidates must produce a "pétition de soutien signée par au
# moins deux pour cent (2%) des électeurs inscrits dans la circonscription"
# before registration can be approved.
#
# BonID collects these endorsements two ways:
#   1. Digital — a verified citizen clicks "Endòse" on the preliminary roster.
#      The row is stamped with the endorser's BonID.
#   2. CSV upload — CEP staff batch-import paper petitions collected in rural
#      areas. Each row carries either a BonID (if we can match) or a CIN with
#      a scanned signature image.
#
# A citizen may not endorse the same candidate twice (enforced at DB level).
class CreateElectionCandidateEndorsements < ActiveRecord::Migration[8.0]
  def change
    create_table :election_candidate_endorsements do |t|
      t.references :election_candidate, null: false, foreign_key: true
      t.references :election, null: false, foreign_key: { to_table: :bonvote_elections }

      t.string  :bonid
      t.string  :cin_number
      t.string  :source, null: false, default: "digital"  # "digital" | "csv"
      t.boolean :voter_roll_verified, null: false, default: false
      t.references :uploaded_by, foreign_key: { to_table: :admin_users }
      t.string  :signature_image_url
      t.text    :notes
      t.datetime :endorsed_at, null: false

      t.timestamps
    end

    add_index :election_candidate_endorsements,
              %i[election_candidate_id bonid],
              unique: true,
              where: "bonid IS NOT NULL",
              name: "idx_endorsement_unique_per_bonid"

    add_index :election_candidate_endorsements,
              %i[election_candidate_id cin_number],
              unique: true,
              where: "cin_number IS NOT NULL AND bonid IS NULL",
              name: "idx_endorsement_unique_per_cin"
  end
end
