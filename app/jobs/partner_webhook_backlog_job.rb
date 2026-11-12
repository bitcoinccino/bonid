# frozen_string_literal: true

# app/jobs/partner_webhook_backlog_job.rb
#
# Delivers consent lifecycle webhooks (consent.revoked / restored / approved,
# bonid.changed) that a partner never received — because they had no webhook
# URL yet, weren't verified, or every retry failed.
#
# Only the LATEST event per consent is sent: if a citizen revoked and then
# restored, the partner needs the final state, not a replay. Older undelivered
# events for the same consent are marked "superseded".
#
# Triggered by:
#   - Partner#flush_webhook_backlog (webhook URL set/changed, partner verified)
#   - WebhookBacklogSweepJob (recurring safety net in production)
class PartnerWebhookBacklogJob < ApplicationJob
  queue_as :webhooks

  CONSENT_EVENTS = %w[consent.revoked consent.restored consent.approved bonid.changed].freeze

  # Statuses that will never be retried on their own.
  BACKLOG_STATUSES = %w[undeliverable dead_letter].freeze

  # A "failed" event whose scheduled retry was lost (e.g. process restart) —
  # the GDPR retry schedule finishes well within this window.
  STUCK_AFTER = 24.hours

  def perform(partner_id)
    partner = Partner.find_by(id: partner_id)
    return unless partner&.webhook_enabled?

    events = self.class.backlog_for(partner).to_a
    return if events.empty?

    events.group_by { |e| e.payload&.dig("consent_id") }.each do |consent_id, group|
      next if consent_id.blank?

      consent = ConsentGrant.find_by(id: consent_id, partner_id: partner.id)
      latest  = latest_event_for(partner, consent_id)

      if consent.nil? || latest.nil? || latest.status == "delivered" || !group.include?(latest)
        # A newer event for this consent already went out (or the consent is gone).
        mark_superseded(group)
        next
      end

      mark_superseded(group - [ latest ])
      BonidNotifier.notify_consent_change(consent, latest.event_type, webhook_event: latest)
    end
  end

  def self.backlog_for(partner)
    ApiWebhookEvent
      .where(partner: partner, direction: "outbound", event_type: CONSENT_EVENTS)
      .where("status IN (:backlog) OR (status = 'failed' AND updated_at < :stuck)",
             backlog: BACKLOG_STATUSES, stuck: STUCK_AFTER.ago)
      .order(:created_at)
  end

  private

  def latest_event_for(partner, consent_id)
    ApiWebhookEvent
      .where(partner: partner, direction: "outbound", event_type: CONSENT_EVENTS)
      .where("payload ->> 'consent_id' = ?", consent_id.to_s)
      .where.not(status: "superseded")
      .order(created_at: :desc)
      .first
  end

  def mark_superseded(events)
    ids = events.map(&:id)
    ApiWebhookEvent.where(id: ids).update_all(status: "superseded", updated_at: Time.current) if ids.any?
  end
end
