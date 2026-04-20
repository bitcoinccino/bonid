# frozen_string_literal: true

module PartnerPortal
  # Single Biwo Vòt (BV) management nested under a Sant Vòt (PollingCenter).
  # Bulk creation continues to flow through PollingCenterImporter; this
  # controller is for one-off corrections (extra BV at a busy center, fixing
  # capacity at a centro that turned out smaller, closing a BV that lost
  # its room).
  #
  # Destroy is blocked when registered_count > 0 — voters are already
  # assigned and yanking the BV would break their receipt links.
  class PollingStationsController < PartnerPortal::BaseController
    before_action :load_center
    before_action :load_station, only: [ :edit, :update, :destroy ]

    def new
      @station = @center.polling_stations.new(
        bv_number: next_bv_number,
        capacity:  450,
        status:    "open"
      )
    end

    def create
      @station = @center.polling_stations.new(station_params)
      @station.registered_count ||= 0

      if @station.save
        audit!("polling_station.created", @station)
        redirect_to partner_portal_polling_center_path(@center),
                    notice: "BV ##{@station.bv_number} kreye."
      else
        flash.now[:alert] = @station.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @station.update(station_params)
        audit!("polling_station.updated", @station,
               changed: @station.previous_changes.except("updated_at").keys)
        redirect_to partner_portal_polling_center_path(@center),
                    notice: "BV ##{@station.bv_number} mete a jou."
      else
        flash.now[:alert] = @station.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @station.registered_count.to_i.positive?
        redirect_to partner_portal_polling_center_path(@center),
                    alert: "Pa ka efase BV ##{@station.bv_number}: gen #{@station.registered_count} votè deja atribye." and return
      end

      bv = @station.bv_number
      audit!("polling_station.destroyed", @station)
      @station.destroy
      redirect_to partner_portal_polling_center_path(@center), notice: "BV ##{bv} efase."
    end

    private

    # Defense-in-depth scoping inherited from PollingCentersController:
    # a BV is reachable only when its parent center is in the active
    # election AND manageable by the current partner. CEP partners see
    # everything; other partners are restricted to their own centers.
    def load_center
      election = active_election
      unless election
        redirect_to partner_portal_polling_centers_path,
                    alert: "Pa gen eleksyon aktif." and return
      end
      # Both the parent center AND the BV are routed by opaque slug, so
      # neither /polling_centers/:n nor .../polling_stations/:n is
      # enumerable by guessing sequential ids.
      @center = election.polling_centers
                        .manageable_by_partner(current_partner)
                        .find_by!(slug: params[:polling_center_id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn(
        "🚨 Polling station IDOR attempt: partner_id=#{current_partner&.id} " \
        "actor=#{current_portal_user&.id} requested_center=#{params[:polling_center_id].inspect}"
      )
      audit!("polling_station.access_denied", nil,
             requested_center_id: params[:polling_center_id])
      redirect_to partner_portal_polling_centers_path,
                  alert: "Sant Vòt sa pa nan òganizasyon w."
    end

    def active_election
      @active_election ||=
        BonvoteElection.where(status: "open").order(opened_at: :desc).first ||
        BonvoteElection.where(status: "draft").order(:election_date).first ||
        BonvoteElection.order(created_at: :desc).first
    end

    def audit!(event, station, extra = {})
      payload = {
        partner_admin_id: current_portal_user&.id,
        partner_admin_email: current_portal_user&.email,
        ip: request.remote_ip,
        user_agent: request.user_agent,
        center_id: @center&.id
      }
      payload[:station_id] = station&.id if station
      payload.merge!(extra)
      PartnerAuditLog.log!(current_partner, current_portal_user, event, payload)
    rescue => e
      Rails.logger.error("PartnerAuditLog write failed: #{e.class}: #{e.message}")
    end

    def load_station
      @station = @center.polling_stations.find_by!(slug: params[:id])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn(
        "🚨 Polling station IDOR attempt: partner_id=#{current_partner&.id} " \
        "actor=#{current_portal_user&.id} requested_station=#{params[:id].inspect}"
      )
      audit!("polling_station.access_denied", nil, requested_station_id: params[:id])
      redirect_to partner_portal_polling_center_path(@center),
                  alert: "BV sa pa egziste."
    end

    def next_bv_number
      (@center.polling_stations.maximum(:bv_number) || 0) + 1
    end

    def station_params
      params.require(:polling_station).permit(:bv_number, :capacity, :status)
    end
  end
end
