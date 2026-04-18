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
    before_action :load_station, only: [:edit, :update, :destroy]

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
      @station.destroy
      redirect_to partner_portal_polling_center_path(@center), notice: "BV ##{bv} efase."
    end

    private

    def load_center
      @center = PollingCenter.find(params[:polling_center_id])
    end

    def load_station
      @station = @center.polling_stations.find(params[:id])
    end

    def next_bv_number
      (@center.polling_stations.maximum(:bv_number) || 0) + 1
    end

    def station_params
      params.require(:polling_station).permit(:bv_number, :capacity, :status)
    end
  end
end
