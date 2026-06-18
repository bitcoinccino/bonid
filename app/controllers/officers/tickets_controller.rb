class Officers::TicketsController < ApplicationController
  include IdpolExtrasPausable # v1 launch: paused unless IDPOL_EXTRAS_ENABLED=true
  pause_unless_idpol_extras

  before_action :authenticate_officer!

    def new
      @ticket = Ticket.new
    end

    def create
      @ticket = current_officer.tickets.build(ticket_params)
      if @ticket.save
        redirect_to officers_dashboard_path, notice: "Ticket submitted successfully."
      else
        render :new, status: :unprocessable_entity
      end
    end

    private

    def ticket_params
      params.require(:ticket).permit(:title, :description, :urgency, :incident_report_id)
    end

end
