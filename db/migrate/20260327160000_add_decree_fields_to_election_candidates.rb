# frozen_string_literal: true

# Add fields required by the Décret Électoral (December 1, 2025)
# Article 180-181: Candidate registration dossier requirements
#
class AddDecreeFieldsToElectionCandidates < ActiveRecord::Migration[7.1]
  def change
    change_table :election_candidates, bulk: true do |t|
      # ── Identity (Article 181) ──
      t.date    :date_of_birth
      t.string  :place_of_birth                            # Commune/Section of birth
      t.string  :nationality, default: "haitian"
      t.string  :sex                                       # M/F per official documents
      t.string  :marital_status                            # celibataire, marie, divorce, veuf
      t.string  :profession

      # ── Address / Residence ──
      t.string  :residence_department                      # Department code
      t.string  :residence_commune                         # Commune name
      t.string  :residence_address                         # Street address
      t.integer :residence_years                           # Years at current residence

      # ── Candidacy Type ──
      t.string  :candidacy_type, default: "party"          # party, independent, grouping
      t.text    :support_petition_details                   # For independents: 2% elector support list

      # ── Required Documents (Article 181 checklist) ──
      t.boolean :doc_birth_certificate, default: false     # Acte de naissance / Extrait des archives
      t.boolean :doc_cin_oni, default: false                # CIN ou certificat ONI
      t.boolean :doc_casier_judiciaire, default: false     # Extrait casier judiciaire (DCPJ)
      t.boolean :doc_dgi_receipt, default: false            # Quittance DGI (frais d'inscription payés)
      t.boolean :doc_property_proof, default: false        # Attestation propriété immobilière (senators/president)
      t.boolean :doc_residence_attestation, default: false # Attestation de résidence
      t.boolean :doc_immigration_cert, default: false      # Certificat d'immigration (if applicable)
      t.boolean :doc_discharge, default: false             # Décharge (if ex-government official)
      t.boolean :doc_passport_photos, default: false       # 4 photos d'identité récentes
      t.boolean :doc_party_mandate, default: false         # Attestation du parti (for party candidates)
      t.boolean :doc_support_petition, default: false      # Pétition 2% électeurs (for independents)
      t.boolean :doc_profession_proof, default: false      # Attestation profession/activité

      # ── Fees (Décret Électoral) ──
      t.integer :registration_fee_gourdes                  # Fee amount in Gourdes
      t.string  :dgi_receipt_number                        # DGI payment reference
      t.boolean :fee_paid, default: false
      t.boolean :fee_reduced, default: false               # 50% reduction for women/disabled/education
      t.string  :fee_reduction_reason                      # woman, disabled, educator

      # ── Récépissé ──
      t.string  :recepisse_number                          # Official receipt number after submission
      t.datetime :recepisse_issued_at
    end

    add_index :election_candidates, :candidacy_type
    add_index :election_candidates, :recepisse_number, unique: true, where: "recepisse_number IS NOT NULL"
  end
end
