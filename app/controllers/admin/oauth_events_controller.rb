module Admin
  class OauthEventsController < Admin::BaseController
    def index
      @events = OauthEvent.includes(:oauth_application, :user).order(created_at: :desc)
      @events = @events.where(oauth_application_id: params[:oauth_application_id]) if params[:oauth_application_id].present?
      @events = @events.where(event_type: params[:event_type]) if params[:event_type].present?
      @events = @events.where(status: params[:status]) if params[:status].present?
      @events = @events.page(params[:page]).per(50)
    end

    def replay
      event = OauthEvent.find(params[:id])
      OauthEventReplayJob.perform_later(event.id)
      redirect_to admin_oauth_events_path, notice: "Replay queued for event ##{event.id}."
    end

    def human_event_type(event)
      {
        "consent_granted" => "Granted",
        "consent_revoked" => "Revoked"
      }[event.event_type] || event.event_type.titleize
    end

    def human_event_status(event)
      {
        "replayed" => "Replay Successful",
        "replay_failed" => "Failed",
        "success" => "Success",
        "failed" => "Failed"
      }[event.status] || event.status.titleize
    end
  end
end
