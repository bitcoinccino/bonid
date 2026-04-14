# frozen_string_literal: true

# Electoral calendar — citizen view.
# Shows election timeline phases that are publicly visible.
module Citizens
  module Election
    class CalendarController < BaseController
      def index
        @election = recent_election
        if @election
          @phases = ElectoralCalendar.where(bonvote_election_id: @election.id)
                                     .public_visible
                                     .chronological
          @current_phase = @phases.find(&:active?)
        else
          @phases = []
          @current_phase = nil
        end
      end
    end
  end
end
