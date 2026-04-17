# frozen_string_literal: true

# Citizen vote verification — "Vòt Mwen Konte"
# Enter a ballot hash to confirm it exists in the public ledger.
module Citizens
  module Election
    class VerifyController < BaseController
      def index
        @election = recent_election
        @prefill_hash = params[:hash].to_s.strip
        @voter_record = @election && VoterEligibilityRecord.check_eligibility(
          election: @election, bonid: current_citizen.bonid
        )
        @has_voted = @voter_record&.has_voted == true
      end

      def check
        @election = recent_election
        ballot_hash = params[:ballot_hash].to_s.strip

        if ballot_hash.blank?
          @error = t("citizens.election.verify_empty")
          render :index
          return
        end

        election_id = @election&.id
        @result = ::Election::AuditService.verify_ballot_presence(ballot_hash, election_id)
        @ballot_hash = ballot_hash
      end
    end
  end
end
