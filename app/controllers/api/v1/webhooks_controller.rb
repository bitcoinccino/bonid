# app/controllers/api/v1/webhooks_controller.rb
module Api
  module V1
    class WebhooksController < Api::V1::BaseController
      # skip_before_action :verify_authenticity_token
      before_action :authenticate_api_key!

      # POST /api/v1/webhooks
      def create
        event = params[:event]
        bonid = params[:bonid]
        status = params[:status]

        if event.blank? || bonid.blank? || status.blank?
          return render json: { error: "Missing required fields" }, status: :bad_request
        end

        ApiWebhookEvent.create!(
          partner: @current_partner,
          event_type: event,
          bonid: bonid,
          payload: params.to_unsafe_h
        )

        render json: { message: "Webhook received", event:, status: }, status: :ok
      rescue => e
        Rails.logger.error("[WEBHOOK_FAIL] #{e.class}: #{e.message}")
        render json: { error: "Failed to record webhook" }, status: :internal_server_error
      end
    end
  end
end
