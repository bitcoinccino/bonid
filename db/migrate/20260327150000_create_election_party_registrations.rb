# frozen_string_literal: true

class CreateElectionPartyRegistrations < ActiveRecord::Migration[7.1]
  def change
    create_table :election_party_registrations do |t|
      t.references :election, null: false, foreign_key: { to_table: :bonvote_elections }
      t.references :user, null: true, foreign_key: true                    # BonID user who submitted

      # ── Party Identity ──
      t.string  :registration_type, null: false, default: "party"          # party, grouping (groupement/regroupement)
      t.string  :party_name,        null: false
      t.string  :party_acronym
      t.string  :representative_name, null: false                          # Représentant officiel ou mandataire
      t.string  :representative_bonid                                      # BonID of representative
      t.string  :representative_cin                                        # CIN du représentant
      t.boolean :is_mandataire,      default: false                        # true if mandataire (not official rep)

      # ── For Groupings Only ──
      t.jsonb   :member_parties,     default: []                           # List of party names in grouping

      # ── Document Checklist (Article 143) ──
      t.boolean :doc_acte_constitutif,     default: false                  # 1. Acte constitutif notarié
      t.boolean :doc_acte_reconnaissance,  default: false                  # 2. Acte de reconnaissance
      t.boolean :doc_statuts,              default: false                  # 3. Statuts du parti
      t.boolean :doc_pv_assemblee,         default: false                  # 4. PV assemblée générale / congrès
      t.boolean :doc_acte_mandataire,      default: false                  # 5. Acte notarié mandataire (if applicable)
      t.boolean :doc_lettre_ministere,     default: false                  # 6. Correspondance Ministère de la Justice
      t.boolean :doc_sigle,                default: false                  # 7. Sigle du parti
      t.boolean :doc_embleme,              default: false                  # 8. Emblème (Logo) en couleur
      t.boolean :doc_cin_representant,     default: false                  # 9. CIN du représentant/mandataire
      t.boolean :doc_logo_numerique,       default: false                  # 10. CD/USB avec logo (JPEG/PNG)

      # ── Grouping-specific documents ──
      t.boolean :doc_liste_partis_signataires, default: false              # Liste des partis signataires
      t.boolean :doc_accord_embleme_unique,    default: false              # Accord emblème unique notarié
      t.boolean :doc_actes_reconnaissance_membres, default: false          # Actes reconnaissance de chaque parti

      # ── Review ──
      t.string  :status, null: false, default: "submitted"                 # submitted, under_review, approved, rejected, withdrawn
      t.text    :rejection_reason
      t.string  :reviewed_by                                               # CEP officer name
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.datetime :approved_at
      t.datetime :rejected_at

      t.timestamps
    end

    add_index :election_party_registrations, [ :election_id, :party_name ], unique: true, name: "idx_party_reg_name"
    add_index :election_party_registrations, [ :election_id, :status ], name: "idx_party_reg_status"
    add_index :election_party_registrations, :registration_type

    # Link candidates to their registered party
    add_reference :election_candidates, :party_registration,
                  foreign_key: { to_table: :election_party_registrations },
                  null: true
  end
end
