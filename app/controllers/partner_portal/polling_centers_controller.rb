# frozen_string_literal: true

require "csv"

module PartnerPortal
  # Partner-facing management of polling centers (Sant Vòt) and their
  # stations (BVs) for the active election. CEP uploads the domestic roster;
  # each consulate uploads its own diaspora roster under the same form.
  #
  # Phase 1 scope: list + CSV import. Manual single-center CRUD and in-place
  # capacity edits are deferred to a follow-up.
  class PollingCentersController < PartnerPortal::BaseController
    def index
      @election = active_election
      @centers  = if @election
                    @election.polling_centers
                             .includes(:polling_stations, :communal_section, :commune)
                             .order(:center_type, :priority, :name)
                  else
                    []
                  end

      @stats = build_stats(@centers)
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
          diplomatic_mission_id notes
        ]
        out << [
          "domestic", "Lycée Saint-Louis de Gonzague", 1800, 10,
          "HT", "Rue Roy", "Delmas 31", "Port-au-Prince", "Ouest", "HT6110",
          1, 3, 15, 217,
          nil, nil
        ]
        out << [
          "diaspora", "Haitian Consulate Miami", 900, 5,
          "US", "259 SW 13th Street", nil, "Miami", "FL", "33130",
          nil, nil, nil, nil,
          "HT-CON-MIA", "Temporary venue"
        ]
      end

      send_data csv, filename: "polling_centers_template.csv", type: "text/csv"
    end

    private

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
