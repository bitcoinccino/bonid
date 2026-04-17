# frozen_string_literal: true

module PartnerPortal
  class PartyRegistrationsController < PartnerPortal::BaseController
    before_action :set_election
    before_action :require_election!, except: [ :index ]
    before_action :set_registration, only: [ :show, :approve, :reject, :start_review, :update_documents ]

    def index
      if @election
        scope = ElectionPartyRegistration.where(election: @election)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(registration_type: params[:type]) if params[:type].present?
        scope = scope.where("party_name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

        @stats = ElectionPartyRegistration.stats_for(@election)
        @registrations = scope.order(created_at: :desc).page(params[:page]).per(25)
      else
        @stats = nil
        @registrations = ElectionPartyRegistration.none.page(1)
      end
    end

    def show; end

    def new
      @registration = ElectionPartyRegistration.new(election: @election)
    end

    def create
      @registration = ElectionPartyRegistration.new(registration_params)
      @registration.election = @election
      @registration.status = "submitted"
      @registration.submitted_at = Time.current

      if @registration.save
        redirect_to partner_portal_party_registration_path(@registration),
                    notice: "Enskripsyon pati #{@registration.party_name} soumèt avèk siksè."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update_documents
      if @registration.update(document_params)
        redirect_to partner_portal_party_registration_path(@registration),
                    notice: "Dokiman yo aktyalize."
      else
        render :show, status: :unprocessable_entity
      end
    end

    def start_review
      @registration.start_review!
      redirect_to partner_portal_party_registration_path(@registration),
                  notice: "Revizyon kòmanse."
    end

    def approve
      if @registration.approve!(reviewer: current_partner_admin&.email || "CEP")
        redirect_to partner_portal_party_registrations_path,
                    notice: "#{@registration.display_name} apwouve. Pati a ka enskri kandida kounye a."
      else
        redirect_to partner_portal_party_registration_path(@registration),
                    alert: "Erè pandan apwobasyon."
      end
    end

    def reject
      reason = params[:rejection_reason].to_s.strip
      if reason.blank?
        redirect_to partner_portal_party_registration_path(@registration),
                    alert: "Rezon rejeksyon obligatwa."
        return
      end

      if @registration.reject!(reviewer: current_partner_admin&.email || "CEP", reason: reason)
        redirect_to partner_portal_party_registrations_path,
                    notice: "#{@registration.display_name} rejte."
      else
        redirect_to partner_portal_party_registration_path(@registration),
                    alert: "Erè pandan rejeksyon."
      end
    end

    private

    def set_election
      @election = BonvoteElection.order(created_at: :desc).first
    end

    def require_election!
      return if @election.present?
      redirect_to partner_portal_party_registrations_path,
                  alert: "Pa gen eleksyon aktif. Kreye yon eleksyon anvan."
    end

    def set_registration
      @registration = ElectionPartyRegistration.find(params[:id])
    end

    def registration_params
      params.require(:election_party_registration).permit(
        :registration_type, :party_name, :party_acronym,
        :representative_name, :representative_bonid, :representative_cin,
        :is_mandataire, member_parties: []
      )
    end

    def document_params
      params.require(:election_party_registration).permit(
        :doc_acte_constitutif, :doc_acte_reconnaissance, :doc_statuts,
        :doc_pv_assemblee, :doc_acte_mandataire, :doc_lettre_ministere,
        :doc_sigle, :doc_embleme, :doc_cin_representant, :doc_logo_numerique,
        :doc_liste_partis_signataires, :doc_accord_embleme_unique,
        :doc_actes_reconnaissance_membres
      )
    end
  end
end
