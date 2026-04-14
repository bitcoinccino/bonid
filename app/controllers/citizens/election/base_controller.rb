# frozen_string_literal: true

# Base controller for citizen-facing election features.
# Requires verified BonID for voting actions.
module Citizens
  module Election
    class BaseController < Citizens::BaseController
      private

      def active_election
        @active_election ||= BonvoteElection.find_by(status: "open")
      end

      def recent_election
        @recent_election ||= active_election || BonvoteElection.order(election_date: :desc).first
      end

      def require_verified_bonid!
        unless current_citizen.bonid_verified?
          redirect_to citizens_dashboard_path,
                      alert: t("citizens.election.not_verified")
        end
      end

      def require_active_election!
        unless active_election
          redirect_to citizens_election_calendar_path,
                      alert: t("citizens.election.no_election")
        end
      end
    end
  end
end
