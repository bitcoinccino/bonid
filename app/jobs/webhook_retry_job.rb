# app/jobs/webhook_retry_job.rb
class WebhookRetryJob < ApplicationJob
  queue_as :webhooks

  def perform(partner_id, event_id, attempt)
    partner = Partner.find_by(id: partner_id)
    event   = ApiWebhookEvent.find_by(id: event_id)
    return unless partner && event

    # Route consent lifecycle events to the consent-specific notifier
    if event.event_type.start_with?("consent.") || event.event_type == "bonid.changed"
      consent = ConsentGrant.find_by(partner: partner, id: event.payload["consent_id"])
      BonidNotifier.notify_consent_change(consent, event.event_type, attempt: attempt) if consent
    else
      BonidNotifier.notify_partner(partner, event, attempt: attempt)
    end
  end
end
