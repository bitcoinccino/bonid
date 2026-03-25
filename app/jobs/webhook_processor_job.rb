# app/jobs/webhook_processor_job.rb
class WebhookProcessorJob < ApplicationJob
  queue_as :webhooks

  # Every event (approved / rejected / revoked) will flow through here.
  def perform(event_id)
    event = ApiWebhookEvent.find(event_id)

    Rails.logger.info("[WebhookProcessorJob] Processing event ##{event.id} (#{event.event_type})")

    # Route event to correct handler
    case event.event_type
    when "approved"  then handle_approval(event)
    when "rejected"  then handle_rejection(event)
    when "revoked"   then handle_revocation(event)
    else
      Rails.logger.warn("[WebhookProcessorJob] Unknown event type: #{event.event_type}")
    end
  rescue => e
    Rails.logger.error("[WebhookProcessorJob] Error: #{e.class} - #{e.message}")
    event.update!(payload: event.payload.merge(error: e.message))
  end

  private

  # === Individual handlers ===
  def handle_approval(event)
    BonidNotifier.notify_partner(event.partner, event)
  end

  def handle_rejection(event)
    BonidNotifier.notify_partner(event.partner, event)
  end

  def handle_revocation(event)
    BonidNotifier.notify_partner(event.partner, event)
  end
end
