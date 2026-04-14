# frozen_string_literal: true

module PartnerPortal
  class VoterRegistryController < PartnerPortal::BaseController
    def index
      @election = BonvoteElection.order(created_at: :desc).first
      return unless @election

      @stats = VoterEligibilityRecord.stats_for(@election)

      scope = VoterEligibilityRecord.where(bonvote_election: @election)
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(department_code: params[:department]) if params[:department].present?
      scope = scope.where(channel: params[:channel]) if params[:channel].present?
      scope = scope.where("bonid ILIKE ?", "%#{params[:search]}%") if params[:search].present?

      @voters = scope.order(created_at: :desc).page(params[:page]).per(50)
    end

    def build
      @election = BonvoteElection.order(created_at: :desc).first

      unless @election
        redirect_to partner_portal_voter_registry_path, alert: "Pa gen eleksyon aktif."
        return
      end

      VoterEligibilityRecord.build_electoral_list!(election: @election)
      redirect_to partner_portal_voter_registry_path, notice: "Lis elektoral la bati avèk siksè."
    end
  end
end
