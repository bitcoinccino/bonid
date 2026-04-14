# frozen_string_literal: true

module PartnerPortal
  class ElectoralCalendarController < PartnerPortal::BaseController
    def index
      @election = BonvoteElection.order(created_at: :desc).first
      @phases = @election ? ElectoralCalendar.timeline_for(@election) : ElectoralCalendar.none
      @current_phase = ElectoralCalendar.current_phase(@election)
    end
  end
end
