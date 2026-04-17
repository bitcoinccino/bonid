# frozen_string_literal: true

class CreateElectionHierarchyTables < ActiveRecord::Migration[7.1]
  def change
    # ── Electoral Bodies (BED / BEC / BCEV) ─────────────────────
    # The CEP's decentralized structure:
    #   CEP (national) → BED (departmental) → BEC (communal) → BCEV (polling station)
    #
    # OAS Report finding: "Departmental Electoral Offices (BED) & Communal Electoral
    # Offices (BEC) handle the local logistics of the election."
    #
    create_table :election_bodies do |t|
      t.references :election, null: false, foreign_key: { to_table: :bonvote_elections }
      t.string  :body_type,      null: false                        # bed, bec, bcev
      t.string  :code,           null: false                        # e.g., "BED-OU", "BEC-OU-PV", "BCEV-OU-PV-001"
      t.string  :name,           null: false                        # "Bureau Electoral Ouest", "BEC Pétion-Ville"
      t.string  :department_code                                    # OU, ND, SD, etc.
      t.string  :department_name                                    # Ouest, Nord, etc.
      t.integer :commune_id                                         # FK to communes (for BEC/BCEV)
      t.integer :arrondissement_id                                  # FK to arrondissements
      t.references :parent_body, foreign_key: { to_table: :election_bodies }, null: true  # BEC → BED, BCEV → BEC
      t.string  :address                                            # Physical location
      t.string  :phone
      t.string  :status,         null: false, default: "active"     # active, closed, suspended
      t.integer :registered_voters, default: 0                      # Voters assigned to this body/station
      t.integer :stations_count, default: 0                         # Number of BCEV under this BEC
      t.jsonb   :metadata,       default: {}                        # Extra config
      t.timestamps
    end

    add_index :election_bodies, [ :election_id, :body_type ]
    add_index :election_bodies, [ :election_id, :code ], unique: true
    add_index :election_bodies, [ :election_id, :department_code ]
    add_index :election_bodies, :commune_id

    # ── Election Accreditations ─────────────────────────────────
    # OAS recommendation: "Issue a personal accreditation pass to each political
    # representative that shows full name, CIN number, photograph, and the
    # polling station where he is registered."
    #
    # Covers: mandataires (party reps), national observers, international observers (EOM)
    #
    create_table :election_accreditations do |t|
      t.references :election, null: false, foreign_key: { to_table: :bonvote_elections }
      t.references :user, null: true, foreign_key: true             # BonID holder (if registered)
      t.string  :accreditation_type, null: false                    # mandataire, national_observer, international_observer
      t.string  :bonid                                              # BonID of accredited person
      t.string  :full_name,       null: false
      t.string  :cin_number                                         # Carte d'Identification Nationale
      t.string  :organization,    null: false                       # Party name or observer org (e.g., "OEA", "RNDDH")
      t.string  :organization_acronym                               # "FL", "PHTK", "OEA", "ONU"
      t.string  :photo_url                                          # CDN path to accreditation photo
      t.string  :accreditation_code, null: false                    # Unique non-transferable code
      t.references :assigned_body, foreign_key: { to_table: :election_bodies }, null: true  # Assigned BEC/BCEV
      t.string  :assigned_station_code                              # BCEV code where they can observe/vote
      t.string  :department_code                                    # Assigned department
      t.string  :status,          null: false, default: "pending"   # pending, active, suspended, revoked
      t.boolean :identity_verified, default: false                  # BonID liveness verified
      t.string  :issued_by                                          # CEP officer who issued
      t.datetime :issued_at
      t.datetime :revoked_at
      t.string :revocation_reason
      t.timestamps
    end

    add_index :election_accreditations, [ :election_id, :accreditation_type ]
    add_index :election_accreditations, [ :election_id, :accreditation_code ], unique: true, name: "idx_accreditations_code"
    add_index :election_accreditations, [ :election_id, :bonid ], unique: true, name: "idx_accreditations_bonid"
    add_index :election_accreditations, :organization

    # ── Election Disputes (BCEN) ────────────────────────────────
    # Bureau du Contentieux Electoral National — Haiti's highest instance
    # for disputes over electoral matters.
    #
    # OAS finding: "The CIEVE reviewed 143 complaints. The BCEN analyzed
    # 78 randomly selected electoral returns... 26 were eliminated."
    #
    create_table :election_disputes do |t|
      t.references :election, null: false, foreign_key: { to_table: :bonvote_elections }
      t.string  :dispute_type,   null: false                        # complaint, challenge, annulment_request, recount_request
      t.string  :reference_code, null: false                        # BCEN-2026-0001
      t.string  :filed_by_type,  null: false                        # candidate, party, observer, citizen
      t.string  :filed_by_name,  null: false
      t.string  :filed_by_bonid                                     # BonID of filer
      t.string  :filed_by_organization                              # Party or org name
      t.references :constituency, foreign_key: { to_table: :election_constituencies }, null: true
      t.references :election_body, foreign_key: { to_table: :election_bodies }, null: true  # Which BED/BEC/BCEV
      t.string  :department_code                                    # Department involved
      t.integer :commune_id                                         # Commune involved
      t.string  :subject,        null: false                        # Brief description
      t.text    :description                                        # Full complaint text
      t.text    :evidence_summary                                   # Summary of evidence provided
      t.jsonb   :attachments,    default: []                        # Document references
      t.string  :status,         null: false, default: "filed"      # filed, under_review, hearing_scheduled, decided, appealed, closed
      t.string  :priority,       default: "normal"                  # low, normal, high, urgent
      t.string  :assigned_to                                        # BCEN officer name
      t.string  :assigned_to_bonid                                  # BCEN officer BonID
      t.text    :decision                                           # BCEN ruling
      t.string  :decision_type                                      # upheld, dismissed, partial, referred
      t.datetime :filed_at
      t.datetime :hearing_at
      t.datetime :decided_at
      t.datetime :appeal_deadline
      t.timestamps
    end

    add_index :election_disputes, [ :election_id, :reference_code ], unique: true, name: "idx_disputes_reference"
    add_index :election_disputes, [ :election_id, :status ]
    add_index :election_disputes, [ :election_id, :dispute_type ]
    add_index :election_disputes, :department_code

    # ── Election Staff Assignments ──────────────────────────────
    # Links CEP team members (users with CEP roles) to specific
    # electoral bodies (BED/BEC/BCEV) for a given election.
    #
    create_table :election_staff_assignments do |t|
      t.references :election, null: false, foreign_key: { to_table: :bonvote_elections }
      t.references :user, null: false, foreign_key: true
      t.references :election_body, null: false, foreign_key: { to_table: :election_bodies }
      t.string  :role,            null: false                        # cep_supervisor, cep_station_staff, cep_trainer, etc.
      t.string  :bonid                                              # Staff member's BonID
      t.string  :status,          null: false, default: "assigned"  # assigned, active, completed, removed
      t.boolean :identity_verified, default: false                  # BonID verified for this assignment
      t.datetime :assigned_at
      t.datetime :checked_in_at                                     # When they arrived at station on election day
      t.datetime :checked_out_at                                    # When they left
      t.timestamps
    end

    add_index :election_staff_assignments, [ :election_id, :user_id, :election_body_id ], unique: true, name: "idx_staff_election_body"
    add_index :election_staff_assignments, [ :election_id, :role ]
    add_index :election_staff_assignments, [ :election_body_id, :role ]
  end
end
