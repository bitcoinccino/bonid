# frozen_string_literal: true

module PartnerPortal
  class ElectionsController < BaseController
    before_action :set_election, only: [:show, :open_election, :close_election, :certify_election, :generate_calendar]

    def index
      @elections = BonvoteElection.order(created_at: :desc).page(params[:page]).per(10)
    end

    def show; end

    def new
      @election = BonvoteElection.new(round: 1, status: "draft")
    end

    def create
      @election = BonvoteElection.new(election_params)
      @election.status = "draft"

      if @election.save
        redirect_to partner_portal_election_path(@election), notice: "Eleksyon kreye avèk siksè."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def open_election
      @election.open!

      # Start the aggregated tally broadcast loop (every 5 seconds)
      BroadcastElectionTallyJob.perform_later(@election.id)
      # Reset the Redis vote counter for a clean start
      ::Election::ElectionCache.reset_vote_counter!(@election.id)
      # Invalidate cached status so all servers see "open" immediately
      ::Election::ElectionCache.invalidate!(@election.id)

      redirect_to partner_portal_election_path(@election), notice: "Eleksyon ouvri — vòt kòmanse!"
    rescue => e
      redirect_to partner_portal_election_path(@election), alert: "Erè: #{e.message}"
    end

    def close_election
      @election.close!
      # Invalidate cache so voting stops within seconds across all servers
      ::Election::ElectionCache.invalidate!(@election.id)

      redirect_to partner_portal_election_path(@election), notice: "Eleksyon fèmen — vòt sispann."
    rescue => e
      redirect_to partner_portal_election_path(@election), alert: "Erè: #{e.message}"
    end

    def certify_election
      @election.certify!
      ::Election::ElectionCache.invalidate!(@election.id)

      redirect_to partner_portal_election_path(@election), notice: "Eleksyon sètifye — rezilta ofisyèl."
    rescue => e
      redirect_to partner_portal_election_path(@election), alert: "Erè: #{e.message}"
    end

    def generate_calendar
      ElectoralCalendar.generate_for!(@election)
      redirect_to partner_portal_election_path(@election),
                  notice: "Kalandriye elektoral 2026 jenere avèk siksè (13 faz ofisyèl CEP)."
    rescue => e
      redirect_to partner_portal_election_path(@election), alert: "Erè: #{e.message}"
    end

    private

    def set_election
      @election = BonvoteElection.find(params[:id])
    end

    def election_params
      params.require(:bonvote_election).permit(:title, :election_type, :election_date, :round, :cep_public_key)
    end
  end
end
