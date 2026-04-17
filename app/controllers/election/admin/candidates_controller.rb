# frozen_string_literal: true

# CEP Admin — Candidate nomination review.
#
# Citizens & parties submit candidacies through the partner portal
# (PartnerPortal::CandidateRegistrationsController). The CEP council
# reviews each file against Articles 180-181 of the Décret Électoral
# and either approves (onto the ballot) or rejects with a reason.
#
# This controller is the CEP-side review surface. Submission stays
# in the partner portal; approval authority stays here.
module Election
  module Admin
    class CandidatesController < ::Admin::BaseController
      include Election::Admin::CepAdminGate

      before_action :set_election
      before_action :set_candidate, only: %i[show start_review approve reject]

      # GET /admin/election/:election_id/candidates
      def index
        scope = ElectionCandidate.where(election: @election)
        scope = scope.where(registration_status: params[:status])   if params[:status].present?
        scope = scope.where(position: params[:position])            if params[:position].present?
        scope = scope.where(candidacy_type: params[:candidacy_type]) if params[:candidacy_type].present?
        if params[:search].present?
          scope = scope.where(
            "full_name ILIKE :q OR party_name ILIKE :q OR bonid ILIKE :q",
            q: "%#{params[:search]}%"
          )
        end

        @stats = ElectionCandidate.registration_stats_for(@election)
        @candidates = scope.order(created_at: :desc).page(params[:page]).per(25)
      end

      # GET /admin/election/:election_id/candidates/:id
      def show
        # Seat-pressure data for the approve modal. We don't block the admin —
        # the CEP keeps discretion — but we surface the picture: how many
        # seats this constituency has, how many are already approved, and
        # the roster so the admin knows who else is on the ballot.
        @constituency = @candidate.election_constituency
        if @constituency
          @seats_available = @constituency.seats.to_i
          constituency_scope = ElectionCandidate.where(
            election: @election,
            election_constituency_id: @constituency.id
          )
          @approved_in_constituency = constituency_scope.approved.where.not(id: @candidate.id).count
          @other_approved = constituency_scope.approved.where.not(id: @candidate.id).order(:full_name)
          @seat_pressure = @seats_available.positive? && @approved_in_constituency >= @seats_available
        else
          @seats_available = 0
          @approved_in_constituency = 0
          @other_approved = ElectionCandidate.none
          @seat_pressure = false
        end
      end

      # POST /admin/election/:election_id/candidates/:id/start_review
      def start_review
        if @candidate.start_review!
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      notice: "Revizyon kòmanse pou #{@candidate.full_name}."
        else
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Revizyon pa ka kòmanse nan estati sa a."
        end
      end

      # POST /admin/election/:election_id/candidates/:id/approve
      def approve
        if @candidate.approve!(admin: current_admin_user)
          redirect_to admin_election_election_candidates_path(@election.id),
                      notice: "#{@candidate.full_name} apwouve — sou bilten vòt la."
        else
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Apwobasyon echwe. Verifye estati enskripsyon an."
        end
      end

      # POST /admin/election/:election_id/candidates/:id/reject
      def reject
        reason = params[:rejection_reason].to_s.strip
        if reason.blank?
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Rezon rejeksyon obligatwa."
          return
        end

        if @candidate.reject!(admin: current_admin_user, reason: reason)
          redirect_to admin_election_election_candidates_path(@election.id),
                      notice: "#{@candidate.full_name} rejte."
        else
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Rejeksyon echwe. Verifye estati enskripsyon an."
        end
      end

      private

      def set_election
        @election = BonvoteElection.find(params[:election_id])
      end

      def set_candidate
        @candidate = ElectionCandidate.where(election: @election).find(params[:id])
      end
    end
  end
end
