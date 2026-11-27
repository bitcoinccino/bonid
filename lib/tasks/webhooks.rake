# frozen_string_literal: true

namespace :webhooks do
  desc "One-time: queue consent.revoked webhooks for revocations that were never recorded " \
       "(before undeliverable events existed). Safe to re-run. DRY_RUN=1 to preview."
  task backfill_revocations: :environment do
    dry_run = ENV["DRY_RUN"].present?

    already_sent = ApiWebhookEvent
      .where(direction: "outbound", event_type: "consent.revoked")
      .pluck(Arel.sql("payload ->> 'consent_id'"))
      .compact.map(&:to_i).to_set

    missing = ConsentGrant.revoked.includes(:partner, :citizen).reject { |c| already_sent.include?(c.id) }

    puts "#{missing.size} revoked consent(s) with no consent.revoked webhook on record#{" (dry run)" if dry_run}"
    missing.each do |consent|
      reachable = consent.partner&.webhook_enabled?
      puts "  consent ##{consent.id} → #{consent.partner&.name} (#{reachable ? "send now" : "hold until webhook URL is set"})"
      BonidNotifier.notify_consent_change(consent, "consent.revoked") unless dry_run
    end
  end
end
