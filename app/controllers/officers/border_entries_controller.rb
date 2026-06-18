# frozen_string_literal: true

module Officers
  class BorderEntriesController < Officers::BaseController
    include IdpolExtrasPausable # v1 launch: paused unless IDPOL_EXTRAS_ENABLED=true (tied to the BonTouris pause)
    pause_unless_idpol_extras

    before_action :authenticate_officer!
    before_action :set_visitor, only: :create

    def index
      @border_entries = BorderEntry.includes(:visitor_submission)
                                   .order(entered_at: :desc)
                                   .limit(50)
    end

    def create
      @border_entry = BorderEntry.create!(
        officer: current_officer,
        visitor_submission: @visitor,
        entry_mode: @visitor.entry_mode,
        port_of_entry: @visitor.port_of_entry,
        entered_at: Time.current,
        transport_provider: @visitor.transport_provider,
        transport_reference: @visitor.transport_reference,
        metadata: { ip: request.remote_ip, device: request.user_agent }
      )

      redirect_to officers_border_entries_path, notice: "✅ Visitor entry logged successfully."
    end

    def mark_exit
      @border_entry = BorderEntry.find(params[:id])
      @border_entry.exit!
      redirect_to officers_border_entries_path, notice: "🚪 Exit recorded for visitor #{@border_entry.visitor_submission.bonid}."
    end

    private

    def set_visitor
      @visitor = VisitorSubmission.find_by!(bonid: params[:bonid])
    end
  end
end
