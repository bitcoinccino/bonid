# frozen_string_literal: true

# Phase 2 of the voter-registry work: relax the schema so BonID becomes a
# convenience layer rather than a gatekeeper.
#
#   - A CEP clerk can register a walk-in who has only a CIN (no BonID).
#     user_id and bonid go nullable; cin_number becomes the identity anchor.
#   - Voters pick a `preferred_channel` ("in_person" default | "online")
#     before the voting window opens. The actual `voted_channel` is stamped
#     when the ballot lands, and `has_voted` is the hard lock that prevents
#     double-voting across channels.
#   - `bonvote_elections.allows_online_voting` is the CEP policy knob that
#     gates whether online ballots are accepted at all for a given election.
#
# This is a pure schema change. `register_voter!` is untouched — the digital
# path still runs unchanged. The analog path + channel wiring ship in the
# follow-up commit that rewrites the registration method.
class SupportInclusiveVoterEnrollment < ActiveRecord::Migration[8.0]
  def change
    # ── 1. Make BonID optional on the voter record ──────────────────
    change_column_null :voter_eligibility_records, :user_id, true
    change_column_null :voter_eligibility_records, :bonid,   true

    # `cin_number` already exists (original voter-registry migration) but is
    # not indexed. Now that it's the primary identity anchor for analog
    # voters, index it and enforce per-election uniqueness via a partial
    # index (only rows where CIN is present — legacy records with nil CIN
    # are allowed through).
    add_index :voter_eligibility_records, :cin_number
    add_index :voter_eligibility_records,
              [ :bonvote_election_id, :cin_number ],
              unique: true,
              where: "cin_number IS NOT NULL",
              name: "idx_voter_election_cin_unique"

    # ── 2. Channel preference + actual voting channel ───────────────
    add_column :voter_eligibility_records, :preferred_channel, :string,
               default: "in_person", null: false
    add_column :voter_eligibility_records, :voted_channel, :string

    # ── 3. Per-election online-voting policy knob (CEP-owned) ───────
    add_column :bonvote_elections, :allows_online_voting, :boolean,
               default: false, null: false
  end
end
