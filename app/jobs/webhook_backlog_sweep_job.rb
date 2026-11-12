# frozen_string_literal: true

# app/jobs/webhook_backlog_sweep_job.rb
#
# Recurring safety net (config/recurring.yml): finds every reachable partner
# with undelivered consent webhooks and queues PartnerWebhookBacklogJob for
# each. Catches anything the on-save trigger in Partner missed.
class WebhookBacklogSweepJob < ApplicationJob
  queue_as :webhooks

  def perform
    partner_ids = ApiWebhookEvent
      .where(direction: "outbound", event_type: PartnerWebhookBacklogJob::CONSENT_EVENTS)
      .where("status IN (:backlog) OR (status = 'failed' AND updated_at < :stuck)",
             backlog: PartnerWebhookBacklogJob::BACKLOG_STATUSES,
             stuck: PartnerWebhookBacklogJob::STUCK_AFTER.ago)
      .distinct
      .pluck(:partner_id)

    Partner.where(id: partner_ids).find_each do |partner|
      PartnerWebhookBacklogJob.perform_later(partner.id) if partner.webhook_enabled?
    end
  end
end
