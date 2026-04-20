# frozen_string_literal: true

require "csv"

module PartnerPortal
  # Partner-facing management of polling centers (Sant Vòt) and their
  # stations (BVs) for the active election. CEP uploads the domestic roster;
  # each consulate uploads its own diaspora roster under the same form.
  #
  # Capabilities:
  #   - Bulk CSV import (#import / #process_import / #template)
  #   - Single-center CRUD (#new / #create / #show / #edit / #update / #destroy)
  #   - BV management lives on the nested PollingStationsController
  class PollingCentersController < PartnerPortal::BaseController
    before_action :load_center,      only: [:show, :edit, :update, :destroy]
    before_action :load_departments, only: [:new, :create, :edit, :update]

    def index
      @election = active_election
      @centers  = if @election
                    @election.polling_centers
                             .manageable_by_partner(current_partner)
                             .includes(:polling_stations, :communal_section, :commune)
                             .order(:center_type, :priority, :name)
                  else
                    []
                  end

      @stats = build_stats(@centers)
    end

    def show
      @stations = @center.polling_stations.order(:bv_number)
    end

    def new
      election = active_election
      unless election
        redirect_to partner_portal_polling_centers_path, alert: "Pa gen eleksyon aktif." and return
      end
      @center = election.polling_centers.new(center_type: "domestic", country_code: "HT", priority: 0)
    end

    def create
      election = active_election
      unless election
        redirect_to partner_portal_polling_centers_path, alert: "Pa gen eleksyon aktif." and return
      end

      @center = election.polling_centers.new(center_params)
      # Server-set ownership — never trust the client form. partner_id and
      # created_by are stripped from strong params and assigned here.
      @center.partner = current_partner
      @center.created_by_partner_admin = current_portal_user
      # Drafts → "planned" so CEP can review before opening; opens → "open"
      # so newly added centers immediately accept voter assignments.
      @center.status ||= (election.status == "open" ? "open" : "planned")

      if @center.save
        audit!("polling_center.created", @center)
        redirect_to partner_portal_polling_center_path(@center),
                    notice: "Sant Vòt kreye. Ajoute BV yo kounye a."
      else
        flash.now[:alert] = @center.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @center.update(center_params)
        audit!("polling_center.updated", @center, changed: @center.previous_changes.except("updated_at").keys)
        redirect_to partner_portal_polling_center_path(@center), notice: "Sant Vòt mete a jou."
      else
        flash.now[:alert] = @center.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # PollingStation has dependent: :restrict_with_error via voter_eligibility_records,
      # but PollingCenter dependent: :destroy will cascade station deletion. Block
      # only if any station has voters assigned.
      if @center.polling_stations.where("registered_count > 0").exists?
        redirect_to partner_portal_polling_center_path(@center),
                    alert: "Pa ka efase: gen votè deja atribye nan sant sa." and return
      end

      audit!("polling_center.destroyed", @center)
      @center.destroy
      redirect_to partner_portal_polling_centers_path, notice: "Sant Vòt efase."
    end

    # GET — render upload form
    def import
      @election = active_election
    end

    # POST — process upload
    def process_import
      @election = active_election

      unless @election
        redirect_to partner_portal_polling_centers_path,
                    alert: "Pa gen eleksyon aktif."
        return
      end

      uploaded = params[:csv_file]
      unless uploaded.respond_to?(:read)
        flash.now[:alert] = "Ou dwe chwazi yon fichye CSV."
        render :import, status: :unprocessable_entity
        return
      end

      @result = ::Election::PollingCenterImporter.call(
        csv_io:   uploaded,
        election: @election
      )

      render :import_results
    rescue ArgumentError => e
      flash.now[:alert] = e.message
      render :import, status: :unprocessable_entity
    end

    # GET — downloadable CSV template
    def template
      csv = CSV.generate do |out|
        out << %w[
          center_type name total_capacity priority
          country_code address_line_1 address_line_2 city state_province postal_code
          department_id arrondissement_id commune_id communal_section_id
          diplomatic_mission_id contact_phone contact_hours notes
        ]
        out << [
          "domestic", "Lycée Saint-Louis de Gonzague", 1800, 10,
          "HT", "Rue Roy", "Delmas 31", "Port-au-Prince", "Ouest", "HT6110",
          1, 3, 15, 217,
          nil, "+509 2812 1234", "Jou eleksyon: 6am-4pm", nil
        ]
        out << [
          "diaspora", "Haitian Consulate Miami", 900, 5,
          "US", "259 SW 13th Street", nil, "Miami", "FL", "33130",
          nil, nil, nil, nil,
          "HT-CON-MIA", "+1 305 859 2003", "Election day: 7am-7pm", "Temporary venue"
        ]
      end

      send_data csv, filename: "polling_centers_template.csv", type: "text/csv"
    end

    private

    # Defense-in-depth scoping. A partner_admin must satisfy BOTH:
    #   1. the center belongs to the active election
    #   2. the center is "manageable" by their partner — CEP sees all,
    #      every other partner sees only what their org created.
    # URL-tampering on /:id where the id is foreign now 404s instead of
    # rendering an editable form against a record they don't own.
    def load_center
      election = active_election
      unless election
        redirect_to partner_portal_polling_centers_path,
                    alert: "Pa gen eleksyon aktif." and return
      end

      # Lookup by opaque slug — the route param is now a UUID, never a
      # sequential integer, so URL enumeration is computationally
      # infeasible (~122 bits of entropy).
      @center = election.polling_centers
                        .manageable_by_partner(current_partner)
                        .find_by!(slug: params[:id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn(
        "🚨 Polling center IDOR attempt: partner_id=#{current_partner&.id} " \
        "actor=#{current_portal_user&.id} requested_id=#{params[:id].inspect}"
      )
      audit!("polling_center.access_denied", nil, requested_id: params[:id])
      redirect_to partner_portal_polling_centers_path,
                  alert: "Sant Vòt sa pa nan òganizasyon w."
    end

    # Audit every state change AND every blocked attempt. PartnerAuditLog
    # only stores admin_user (AdminUser); we encode the PartnerAdmin id
    # into metadata so traceability never depends on a future schema add.
    def audit!(event, center, extra = {})
      payload = {
        partner_admin_id: current_portal_user&.id,
        partner_admin_email: current_portal_user&.email,
        ip: request.remote_ip,
        user_agent: request.user_agent
      }
      payload[:center_id]   = center&.id   if center
      payload[:center_name] = center&.name if center
      payload.merge!(extra)
      PartnerAuditLog.log!(current_partner, current_portal_user, event, payload)
    rescue => e
      Rails.logger.error("PartnerAuditLog write failed: #{e.class}: #{e.message}")
    end

    # Required by the shared `address` Stimulus cascade — the controller reads
    # the slug map off the department <select> at connect time.
    def load_departments
      @departments = Department.order(:name)
    end

    def center_params
      params.require(:polling_center).permit(
        :name, :center_type, :venue_type, :expected_capacity, :status, :priority,
        :country_code, :address_line_1, :address_line_2, :city, :state_province, :postal_code,
        :department_id, :arrondissement_id, :commune_id, :communal_section_id,
        :diplomatic_mission_id, :contact_phone, :contact_hours, :notes,
        operating_hours: {}
      )
    end

    # Prefer the election citizens and clerks will actually interact with:
    # the one that's currently open. Fall back to the nearest draft, then the
    # most recent record, so draft-configuration and post-mortem review still
    # land on something sensible.
    def active_election
      @active_election ||=
        BonvoteElection.where(status: "open").order(opened_at: :desc).first ||
        BonvoteElection.where(status: "draft").order(:election_date).first ||
        BonvoteElection.order(created_at: :desc).first
    end

    def build_stats(centers)
      {
        total_centers:     centers.size,
        domestic_centers:  centers.count { |c| c.center_type == "domestic" },
        diaspora_centers:  centers.count { |c| c.center_type == "diaspora" },
        total_stations:    centers.sum { |c| c.polling_stations.size },
        total_capacity:    centers.sum { |c| c.polling_stations.sum(&:capacity) },
        total_registered:  centers.sum { |c| c.polling_stations.sum(&:registered_count) }
      }
    end
  end
end
