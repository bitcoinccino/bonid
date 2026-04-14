# frozen_string_literal: true

# Citizen-facing election results dashboard.
# Read-only view of public results data.
module Citizens
  module Election
    class ResultsController < BaseController
      def index
        @election = recent_election

        if @election
          ballot_stats = ElectionBallot.stats(@election.id) rescue {}
          @total_votes = ballot_stats[:total_votes] || 0
          @remote_votes = ballot_stats[:remote_votes] || 0
          @consulate_votes = ballot_stats[:consulate_votes] || 0
          @countries_count = (ballot_stats[:by_country] || {}).size
          @certified = @election.status == "certified"

          if @certified
            @candidates = ElectionCandidate.where(election_id: @election.id, position: "president", status: "active")
                                           .order(votes_round1: :desc).to_a rescue []
          end
        else
          @total_votes = 0
          @remote_votes = 0
          @consulate_votes = 0
          @countries_count = 0
          @certified = false
        end
      end
    end
  end
end
