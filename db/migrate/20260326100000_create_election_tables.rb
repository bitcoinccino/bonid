# frozen_string_literal: true

class CreateElectionTables < ActiveRecord::Migration[7.1]
  def change
    # ── Elections ─────────────────────────────────────────────────
    # One row per election event (e.g. "2026 General Election").
    # Supports the Haitian two-round absolute-majority system.
    create_table :bonvote_elections do |t|
      t.string  :title,          null: false                        # "Eleksyon Jeneral 2026"
      t.string  :election_type,  null: false                        # general, presidential, legislative, referendum
      t.integer :round,          null: false, default: 1            # 1 = first round, 2 = runoff
      t.references :parent_election, foreign_key: { to_table: :bonvote_elections }, null: true # round-2 → round-1
      t.string  :status,         null: false, default: "draft"      # draft, open, closed, certified, cancelled
      t.date    :election_date,  null: false                        # Aug 30, 2026
      t.datetime :opened_at                                         # when voting opens
      t.datetime :closed_at                                         # when voting closes
      t.datetime :certified_at                                      # when CEP certifies results
      t.string  :cep_public_key                                     # RSA public key for this election
      t.jsonb   :metadata,       default: {}                        # extra config (voting hours, etc.)
      t.timestamps
    end

    add_index :bonvote_elections, :status
    add_index :bonvote_elections, [:election_type, :round]

    # ── Constituencies ───────────────────────────────────────────
    # Maps senate/deputy seats to geographic areas.
    # Haiti: 10 departments × 3 senate seats (1/3 per cycle = 10 up),
    #        99 deputy single-member constituencies.
    create_table :election_constituencies do |t|
      t.references :election, null: false, foreign_key: { to_table: :bonvote_elections }
      t.string  :position,       null: false                        # president, senator, deputy
      t.string  :department_code                                    # OU, ND, SD, etc. (for senator/deputy)
      t.string  :department_name                                    # Ouest, Nord, etc.
      t.integer :commune_id                                         # FK to communes (for deputy)
      t.integer :arrondissement_id                                  # FK to arrondissements (for deputy)
      t.string  :constituency_name, null: false                     # "Prezidan", "Senatè — Ouest", "Depite — Pétion-Ville"
      t.integer :seats,          null: false, default: 1            # seats to fill (usually 1)
      t.boolean :up_for_election, null: false, default: true        # senate rotation: only 1/3 each cycle
      t.string  :electoral_system, null: false, default: "absolute_majority_two_round" # or plurality
      t.timestamps
    end

    add_index :election_constituencies, [:election_id, :position]
    add_index :election_constituencies, [:election_id, :department_code]

    # ── Candidates ───────────────────────────────────────────────
    # One row per candidate per constituency per election.
    create_table :election_candidates do |t|
      t.references :election,      null: false, foreign_key: { to_table: :bonvote_elections }
      t.references :election_constituency, null: false, foreign_key: true
      t.string  :position,         null: false                      # president, senator, deputy
      t.string  :full_name,        null: false
      t.string  :party_name                                         # "Haitian Tèt Kale Party", etc.
      t.string  :party_acronym                                      # "PHTK", "FL", etc.
      t.string  :photo_url                                          # CDN path to candidate photo
      t.string  :department_code                                    # for senator
      t.integer :commune_id                                         # for deputy
      t.integer :ballot_number                                      # position on ballot (CEP assigns)
      t.integer :votes_round1,     default: 0                       # tally after round 1
      t.integer :votes_round2,     default: 0                       # tally after round 2 (if applicable)
      t.boolean :qualified_runoff, default: false                    # top-2 advance to round 2
      t.boolean :winner,           default: false                    # final winner
      t.string  :status,           default: "active"                # active, withdrawn, disqualified
      t.timestamps
    end

    add_index :election_candidates, [:election_id, :position]
    add_index :election_candidates, [:election_id, :department_code]

    # ── Ballots ──────────────────────────────────────────────────
    # Append-only, immutable. One row per vote cast.
    # No PII — only cryptographic hashes and encrypted payloads.
    create_table :election_ballots do |t|
      t.references :election,      null: false, foreign_key: { to_table: :bonvote_elections }
      t.string  :nullifier,        null: false                      # HMAC-derived, prevents double-voting
      t.string  :position,         null: false                      # president, senator, deputy
      t.text    :encrypted_choice, null: false                      # AES-256-GCM ciphertext
      t.text    :encrypted_key                                      # RSA-wrapped AES key
      t.string  :iv                                                 # AES initialization vector
      t.string  :auth_tag                                           # GCM authentication tag
      t.string  :zkp_commitment,   null: false                      # Pedersen commitment
      t.jsonb   :zkp_proof,        default: {}                      # { challenge:, response:, public_commitment: }
      t.string  :ballot_hash,      null: false                      # SHA256 of ballot contents
      t.string  :receipt_id,       null: false                      # UUID for voter receipt
      t.string  :channel,          null: false, default: "remote"   # remote, consulate
      t.string  :consulate_id                                       # which consulate (if channel=consulate)
      t.string  :station_id                                         # kiosk station ID
      t.string  :department_code                                    # voter's department (for geographic tally)
      t.string  :ip_country                                         # geo-IP country code
      t.boolean :location_flagged, default: false                   # BonID location ≠ IP country
      t.datetime :cast_at,         null: false                      # when vote was cast
      t.timestamps
    end

    add_index :election_ballots, [:election_id, :nullifier], unique: true, name: "idx_ballots_election_nullifier"
    add_index :election_ballots, :ballot_hash, unique: true
    add_index :election_ballots, :receipt_id, unique: true
    add_index :election_ballots, [:election_id, :position]
    add_index :election_ballots, [:election_id, :channel]
    add_index :election_ballots, [:election_id, :department_code]
    add_index :election_ballots, :cast_at

    # ── Multi-Sig Signatures ────────────────────────────────────
    # Tracks the 3-of-5 quorum for decryption ceremony.
    create_table :election_signatures do |t|
      t.references :election,      null: false, foreign_key: { to_table: :bonvote_elections }
      t.string  :bonid,            null: false
      t.string  :role,             null: false                      # cep_president, cep_secretary, etc.
      t.string  :signatory_name,   null: false
      t.string  :liveness_session_id                                # biometric verification
      t.boolean :liveness_verified, default: false
      t.string  :key_shard_hash                                     # hash of Shamir shard
      t.datetime :signed_at,       null: false
      t.timestamps
    end

    add_index :election_signatures, [:election_id, :role], unique: true
    add_index :election_signatures, [:election_id, :bonid], unique: true
  end
end
