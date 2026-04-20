# frozen_string_literal: true

# Décret Électoral Articles 192-195: before the liste définitive is
# published, CEP first posts a liste préliminaire. Any voter has 48 hours
# from that posting to file a contestation before the electoral tribunal.
#
# This migration adds the two timestamp columns CEP stamps when it
# publishes each list, plus a FK on disputes so a contestation can name
# the specific candidate being challenged.
class AddPreliminaryListingToElectionCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :election_candidates, :preliminary_listed_at, :datetime
    add_column :election_candidates, :final_listed_at, :datetime

    add_index :election_candidates, :preliminary_listed_at,
              where: "preliminary_listed_at IS NOT NULL",
              name: "idx_candidates_preliminary_listed"

    add_reference :election_disputes, :election_candidate,
                  foreign_key: true, null: true
  end
end
