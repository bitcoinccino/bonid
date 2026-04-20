# frozen_string_literal: true

module PartnerPortal
  # Per-election diaspora-mission CRUD for the CEP partner portal.
  #
  # The 38 Haitian embassies/consulates themselves are static (defined in
  # the HaitianDiplomaticMissions concern). What's editable is the
  # ElectionMissionParticipation row layered on top: per the active CEP
  # election cycle, which missions are participating, in what status, with
  # what hours, contact info, etc.
  #
  # The index lists ALL 38 missions grouped by region with their status
  # ("Pa konfigire" if no participation row exists yet, or the participation
  # status badge). Clicking through to "Konfigire" opens the form.
  class DiplomaticMissionsController < PartnerPortal::BaseController
    include HaitianDiplomaticMissions

    before_action :ensure_cep_sector!
    before_action :require_partner_admin!, only: %i[new create edit update destroy]
    before_action :load_active_election
    before_action :set_participation,      only: %i[edit update destroy]

    # GET /partner_portal/diplomatic_missions
    #
    # Renders the full mission inventory with per-mission status. Uses one
    # IN-query to load all participation rows for the current election so
    # the view doesn't N+1 across 38 rows.
    def index
      @region_filter = params[:region] if HaitianDiplomaticMissions::REGIONS.key?(params[:region])
      @status_filter = params[:status] if ElectionMissionParticipation::STATUSES.include?(params[:status])

      @participations_by_id =
        if @election
          ElectionMissionParticipation.for_election(@election.id).index_by(&:diplomatic_mission_id)
        else
          {}
        end

      missions = ALL_MISSIONS
      missions = missions.select { |m| m[:region] == @region_filter } if @region_filter
      if @status_filter
        missions = missions.select do |m|
          p = @participations_by_id[m[:id]]
          if @status_filter == "unconfigured"
            p.nil?
          else
            p&.status == @status_filter
          end
        end
      end
      if params[:q].present?
        q = params[:q].to_s.downcase
        missions = missions.select { |m| m[:name].downcase.include?(q) || m[:id].downcase.include?(q) }
      end

      @missions = missions
      @counts = {
        total:             ALL_MISSIONS.size,
        configured:        @participations_by_id.size,
        registration_open: @participations_by_id.values.count { |p| p.status == "registration_open" },
        voting_open:       @participations_by_id.values.count { |p| p.status == "voting_open" },
        closed:            @participations_by_id.values.count { |p| p.status == "closed" }
      }
    end

    # GET /partner_portal/diplomatic_missions/new?mission_id=HT-CON-MIA
    def new
      mission_id = params[:mission_id].to_s
      unless ALL_MISSIONS.any? { |m| m[:id] == mission_id }
        redirect_to partner_portal_diplomatic_missions_path,
                    alert: "Misyon pa egziste."
        return
      end
      if @election.nil?
        redirect_to partner_portal_diplomatic_missions_path,
                    alert: "Pa gen eleksyon aktiv pou konfigire."
        return
      end
      @participation = ElectionMissionParticipation.new(
        election: @election,
        diplomatic_mission_id: mission_id,
        status: "registration_open"
      )
    end

    # POST /partner_portal/diplomatic_missions
    def create
      @participation = ElectionMissionParticipation.new(participation_params.merge(election: @election))
      if @participation.save
        redirect_to partner_portal_diplomatic_missions_path,
                    notice: "Misyon konfigire: #{@participation.display_label}"
      else
        render :new, status: :unprocessable_entity
      end
    end

    # GET /partner_portal/diplomatic_missions/:id/edit
    def edit; end

    # PATCH /partner_portal/diplomatic_missions/:id
    def update
      if @participation.update(participation_params)
        redirect_to partner_portal_diplomatic_missions_path,
                    notice: "Misyon mete ajou: #{@participation.display_label}"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /partner_portal/diplomatic_missions/:id
    def destroy
      label = @participation.display_label
      @participation.destroy
      redirect_to partner_portal_diplomatic_missions_path,
                  notice: "Konfigirasyon retire pou: #{label}"
    end

    private

    def set_participation
      @participation = ElectionMissionParticipation.find(params[:id])
    end

    def load_active_election
      @election = BonvoteElection.order(created_at: :desc).first
    end

    # Strong params for everything except operating_hours, which uses the
    # same hand-rolled sanitizer pattern as ElectoralOffice (Rails strong
    # params can't express index-keyed nested hashes cleanly).
    def participation_params
      base = params.require(:election_mission_participation).permit(
        :diplomatic_mission_id, :status, :contact_phone, :contact_email, :notes,
        :street_line1, :street_line2, :locality, :region, :postal_code,
        :latitude, :longitude
      )
      base[:operating_hours] = sanitize_operating_hours(
        params.dig(:election_mission_participation, :operating_hours)
      )
      base
    end

    def sanitize_operating_hours(raw)
      return {} if raw.blank?
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      HasOperatingHours::DAYS.each_with_object({}) do |day, acc|
        day_hash = raw[day] || raw[day.to_sym]
        next if day_hash.blank?
        slots = Array(day_hash.respond_to?(:values) ? day_hash.values : day_hash)
        acc[day] = slots.map { |s| { "open" => s["open"].to_s, "close" => s["close"].to_s } }
      end
    end

    # CEP-only surface (mirrors ElectoralOfficesController#ensure_cep_sector!).
    def ensure_cep_sector!
      sector = (@current_partner.department_sector || @current_partner.sector).to_s.downcase
      return if sector == "cep"
      redirect_to partner_portal_dashboard_path,
                  alert: "Aksè refize. Sèlman patnè CEP ka jere misyon diplomatik."
    end

    def require_partner_admin!
      return if current_portal_user&.has_role?(:partner_admin)
      redirect_to partner_portal_diplomatic_missions_path,
                  alert: "Sèlman administratè ka jere konfigirasyon misyon."
    end
  end
end
