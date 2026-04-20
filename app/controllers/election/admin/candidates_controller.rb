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
      before_action :set_candidate, only: %i[show start_review publish_preliminary approve reject endorsements upload_endorsements]

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

      # POST /admin/election/:election_id/candidates/:id/publish_preliminary
      # Article 192: CEP posts candidate to the liste préliminaire and opens
      # the 48-hour contestation window.
      def publish_preliminary
        # Article 181.15 gate — independent candidates need 2% first. Check
        # here to return a message specific to the petition threshold rather
        # than a generic "can't publish" error.
        if @candidate.independent? && !@candidate.petition_satisfied?
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Kandida endepandan bezwen #{@candidate.petition_threshold} endòsman " \
                             "(2% — Atik 181.15). Li gen sèlman #{@candidate.endorsement_count}."
          return
        end

        if @candidate.publish_to_preliminary!(admin: current_admin_user)
          redirect_to admin_election_election_candidates_path(@election.id),
                      notice: "#{@candidate.full_name} sou lis preliminè — fenèt kontestasyon 48h louvri."
        else
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Pa ka pibliye sou lis preliminè nan estati sa a."
        end
      end

      # POST /admin/election/:election_id/candidates/:id/approve
      # Article 195: final-list promotion. Requires:
      #   1. Candidate is on the preliminary list
      #   2. The 48-hour contestation window has elapsed
      #   3. No upheld objections remain
      def approve
        unless @candidate.registration_status == "preliminary_listed"
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Kandida dwe sou lis preliminè anvan pibliye sou lis definitif."
          return
        end

        if @candidate.contestation_window_open?
          closes_at = I18n.l(@candidate.contestation_window_closes_at, format: :short)
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Fenèt kontestasyon 48h ap fèmen #{closes_at}. Tann anvan w pibliye lis definitif."
          return
        end

        pending_disputes = ElectionDispute.where(
          election_candidate_id: @candidate.id,
          status: %w[filed under_review hearing_scheduled]
        ).count
        if pending_disputes.positive?
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Gen #{pending_disputes} kontestasyon ki poko deside. Dispoze yo anvan."
          return
        end

        if @candidate.approve!(admin: current_admin_user)
          redirect_to admin_election_election_candidates_path(@election.id),
                      notice: "#{@candidate.full_name} apwouve — sou lis definitif la."
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

      # GET /admin/election/:election_id/candidates/:id/endorsements
      # Article 181.15 — roster of all endorsements for this independent
      # candidate. Admins use this to audit paper uploads.
      def endorsements
        @endorsements = ElectionCandidateEndorsement
                          .where(election_candidate_id: @candidate.id)
                          .order(created_at: :desc)
                          .page(params[:page]).per(50)
        @digital_count = ElectionCandidateEndorsement
                           .where(election_candidate_id: @candidate.id, source: "digital").count
        @csv_count = ElectionCandidateEndorsement
                       .where(election_candidate_id: @candidate.id, source: "csv").count
        @verified_count = @candidate.endorsement_count
      end

      # POST /admin/election/:election_id/candidates/:id/upload_endorsements
      # Article 181.15 — bulk import paper-petition signatures collected in
      # rural areas. CSV is parsed by Election::EndorsementCsvImporter which
      # looks up each CIN against the voter roll; rows matched against a
      # VoterEligibilityRecord are auto-verified and count toward the 2%.
      def upload_endorsements
        unless @candidate.independent?
          redirect_to admin_election_election_candidate_path(@election.id, @candidate),
                      alert: "Sèlman kandida endepandan yo bezwen petisyon sipò."
          return
        end

        file = params[:csv_file]
        if file.blank?
          redirect_to admin_election_election_candidate_endorsements_path(@election.id, @candidate),
                      alert: "Chwazi yon fichye CSV."
          return
        end

        result = Election::EndorsementCsvImporter.new(
          candidate: @candidate,
          csv_io: file.tempfile,
          admin: current_admin_user
        ).call

        msg = "Enpòte: #{result.imported} " \
              "(verifye kont wòl: #{result.verified}, pa verifye: #{result.unverified}, " \
              "doublon: #{result.duplicates})."
        msg += " Erè: #{result.errors.size}." if result.errors.any?

        redirect_to admin_election_election_candidate_endorsements_path(@election.id, @candidate),
                    notice: msg
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
