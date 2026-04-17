# frozen_string_literal: true

class AddVoterEligibilityAndCandidateRegistration < ActiveRecord::Migration[8.0]
  def change
    # ── 1. Voter Registry (Lis Elektoral) ──────────────────────────
    # Lightweight lookup: BonID holder → eligible? → which constituency?
    # ONI manages identity; CEP just needs eligibility + constituency mapping.
    create_table :voter_eligibility_records do |t|
      t.references :bonvote_election, null: false, foreign_key: { on_delete: :cascade }
      t.references :user,             null: false, foreign_key: true
      t.string     :bonid,            null: false
      t.string     :cin_number
      t.string     :department_code,   null: false
      t.integer    :commune_id
      t.string     :constituency_name
      t.string     :status,           null: false, default: "eligible"
      t.string     :channel,          default: "domestic"
      t.string     :ineligibility_reason
      t.boolean    :has_voted,        default: false, null: false
      t.datetime   :voted_at
      t.datetime   :verified_at

      t.timestamps
    end

    add_index :voter_eligibility_records, [ :bonvote_election_id, :bonid ], unique: true, name: "idx_voter_election_bonid"
    add_index :voter_eligibility_records, [ :bonvote_election_id, :department_code ], name: "idx_voter_election_dept"
    add_index :voter_eligibility_records, :status
    add_index :voter_eligibility_records, :has_voted

    # ── 2. Candidate Registration Fields ───────────────────────────
    # Extend existing election_candidates with registration workflow
    change_table :election_candidates do |t|
      t.references :user, foreign_key: true
      t.string     :bonid
      t.string     :cin_number
      t.string     :registration_status, default: "draft"
      t.text       :platform_statement
      t.text       :rejection_reason
      t.datetime   :submitted_at
      t.datetime   :approved_at
      t.datetime   :rejected_at
      t.bigint     :approved_by_id
      t.bigint     :rejected_by_id
    end

    add_index :election_candidates, :registration_status
    add_index :election_candidates, [ :election_id, :bonid ], name: "idx_candidate_election_bonid"
    add_foreign_key :election_candidates, :admin_users, column: :approved_by_id
    add_foreign_key :election_candidates, :admin_users, column: :rejected_by_id
  end
end
