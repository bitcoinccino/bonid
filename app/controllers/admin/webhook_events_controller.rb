module Admin
  class WebhookEventsController < Admin::BaseController
    def index
      # Use the correct model
      @logs = ApiWebhookEvent.includes(:partner).order(created_at: :desc)

      # Filters
      @logs = @logs.where(partner_id: params[:partner_id]) if params[:partner_id].present?
      @logs = @logs.where(event_type: params[:event_type]) if params[:event_type].present?

      # Pagination
      @logs = @logs.page(params[:page]).per(50)
    end
  end
end
