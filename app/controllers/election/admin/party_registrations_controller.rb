# frozen_string_literal: true

# CEP Admin — Political party / grouping registration review.
#
# Article 143 of the Décret Électoral: a party or regroupement must
# submit a documented file to the CEP before it can nominate candidates.
# Citizens / party operators submit through the partner portal; the CEP
# council reviews and approves here. An approved registration unlocks
# candidate nominations (ElectionCandidate.party_registration_id).
module Election
  module Admin
    class PartyRegistrationsController < ::Admin::BaseController
      include Election::Admin::CepAdminGate

      before_action :set_election
      before_action :set_registration, only: %i[show start_review approve reject]

      # GET /admin/election/:election_id/party_registrations
      def index
        scope = ElectionPartyRegistration.where(election: @election)
        scope = scope.where(status: params[:status])                     if params[:status].present?
        scope = scope.where(registration_type: params[:registration_type]) if params[:registration_type].present?
        if params[:search].present?
          scope = scope.where(
            "party_name ILIKE :q OR party_acronym ILIKE :q OR representative_name ILIKE :q",
            q: "%#{params[:search]}%"
          )
        end

        @stats = ElectionPartyRegistration.stats_for(@election)
        @registrations = scope.order(created_at: :desc).page(params[:page]).per(25)
      end

      # GET /admin/election/:election_id/party_registrations/:id
      def show; end

      # POST /admin/election/:election_id/party_registrations/:id/start_review
      def start_review
        if @registration.start_review!
          redirect_to admin_election_election_party_registration_path(@election.id, @registration),
                      notice: "Revizyon kòmanse pou #{@registration.display_name}."
        else
          redirect_to admin_election_election_party_registration_path(@election.id, @registration),
                      alert: "Revizyon pa ka kòmanse nan estati sa a."
        end
      end

      # POST /admin/election/:election_id/party_registrations/:id/approve
      def approve
        if @registration.approve!(admin: current_admin_user)
          redirect_to admin_election_election_party_registrations_path(@election.id),
                      notice: "#{@registration.display_name} apwouve — pati a ka enskri kandida kounye a."
        else
          redirect_to admin_election_election_party_registration_path(@election.id, @registration),
                      alert: "Apwobasyon echwe. Verifye estati enskripsyon an."
        end
      end

      # POST /admin/election/:election_id/party_registrations/:id/reject
      def reject
        reason = params[:rejection_reason].to_s.strip
        if reason.blank?
          redirect_to admin_election_election_party_registration_path(@election.id, @registration),
                      alert: "Rezon rejeksyon obligatwa."
          return
        end

        if @registration.reject!(admin: current_admin_user, reason: reason)
          redirect_to admin_election_election_party_registrations_path(@election.id),
                      notice: "#{@registration.display_name} rejte."
        else
          redirect_to admin_election_election_party_registration_path(@election.id, @registration),
                      alert: "Rejeksyon echwe. Verifye estati enskripsyon an."
        end
      end

      private

      def set_election
        @election = BonvoteElection.find(params[:election_id])
      end

      def set_registration
        @registration = ElectionPartyRegistration.where(election: @election).find(params[:id])
      end
    end
  end
end
