# frozen_string_literal: true

# Article 181.15: an independent candidate must collect endorsements from
# at least 2% of registered voters in their constituency before CEP can
# place them on the preliminary list.
#
# A verified citizen endorses by POST'ing to this controller. We require:
#   - BonID verified
#   - Target candidate is `candidacy_type: "independent"`
#   - Target candidate is still `submitted` or `under_review`
#     (you cannot endorse someone already on the preliminary list)
#   - Citizen has not endorsed this candidate already
#
# The resulting row is auto-marked `voter_roll_verified: true` because we
# gate on BonID verification — i.e. the citizen is already on BonID's
# integrated voter roll.
module Citizens
  module Election
    class EndorsementsController < BaseController
      before_action :require_verified_bonid!
      before_action :set_candidate

      # POST /citizens/election/kandida/:election_candidate_id/endose
      def create
        return redirect_with_alert("Sèlman kandida endepandan yo bezwen endòsman.") unless @candidate.independent?
        return redirect_with_alert("Kandida sa a pa aksepte endòsman ankò.") unless accepting_endorsements?

        endorsement = ElectionCandidateEndorsement.new(
          election_candidate: @candidate,
          election: @candidate.election,
          bonid: current_citizen.bonid,
          source: "digital",
          voter_roll_verified: true
        )

        if endorsement.save
          redirect_to election_public_candidates_path(election_id: @candidate.election_id),
                      notice: "Mèsi — endòsman w konte pou #{@candidate.full_name}."
        else
          redirect_with_alert(endorsement.errors.full_messages.to_sentence.presence || "Pa ka endose.")
        end
      end

      # DELETE /citizens/election/kandida/:election_candidate_id/endose
      def destroy
        endorsement = ElectionCandidateEndorsement.find_by(
          election_candidate_id: @candidate.id,
          bonid: current_citizen.bonid
        )

        if endorsement && accepting_endorsements?
          endorsement.destroy
          redirect_to election_public_candidates_path(election_id: @candidate.election_id),
                      notice: "Endòsman w retire."
        else
          redirect_with_alert("Pa ka retire endòsman an.")
        end
      end

      private

      def set_candidate
        @candidate = ElectionCandidate.find(params[:election_candidate_id])
      end

      def accepting_endorsements?
        @candidate.registration_status.in?(%w[draft submitted under_review])
      end

      def redirect_with_alert(msg)
        redirect_to election_public_candidates_path(election_id: @candidate.election_id), alert: msg
      end
    end
  end
end
