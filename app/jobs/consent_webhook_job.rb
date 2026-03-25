# frozen_string_literal: true

# app/jobs/consent_webhook_job.rb
#
# Fires webhook notifications to partners when consent status changes:
#   - consent.revoked   — citizen revoked partner access
#   - consent.restored  — citizen re-granted partner access
#   - consent.approved  — citizen approved a new consent request
#   - bonid.changed     — citizen's BonID changed (name change)
#
class ConsentWebhookJob < ApplicationJob
  queue_as :webhooks

  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(consent_grant_id, event_type)
    consent = ConsentGrant.find_by(id: consent_grant_id)
    return unless consent

    BonidNotifier.notify_consent_change(consent, event_type)
  end
end
