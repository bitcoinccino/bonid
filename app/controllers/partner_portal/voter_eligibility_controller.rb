# frozen_string_literal: true

module PartnerPortal
  class VoterEligibilityController < PartnerPortal::BaseController
    def index
      @election = BonvoteElection.order(created_at: :desc).first
    end

    def lookup
      @election = BonvoteElection.order(created_at: :desc).first

      unless @election
        flash.now[:alert] = "Pa gen eleksyon aktif."
        return render :index
      end

      bonid = params[:bonid].to_s.strip.upcase
      @record = VoterEligibilityRecord.check_eligibility(election: @election, bonid: bonid)

      unless @record
        # Try to find user and register on the fly
        user = User.find_by(bonid: bonid)
        if user
          @record = VoterEligibilityRecord.register_voter!(election: @election, user: user)
        end
      end

      render :index
    end
  end
end
