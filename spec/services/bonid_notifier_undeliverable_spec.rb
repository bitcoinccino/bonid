# frozen_string_literal: true

require "rails_helper"

# A partner must always end up learning about consent changes (especially
# revocations), even if they configure their webhook URL after the fact.
RSpec.describe "Consent webhooks for partners that can't receive them yet" do
  let(:citizen) { create(:user) }
  let(:partner) { create(:partner, :approved, webhook_url: nil, webhook_secret: SecureRandom.hex(16)) }

  def revoked_grant
    ConsentGrant.create!(
      citizen: citizen, partner: partner,
      requested_scopes: %w[openid profile], granted_scopes: %w[openid profile],
      status: :revoked, granted_at: 1.day.ago, revoked_at: Time.current,
      change_reason: "citizen_revoked", expires_at: 89.days.from_now
    )
  end

  def ok_response
    Net::HTTPOK.new("1.1", "200", "OK").tap { |r| allow(r).to receive(:body).and_return("") }
  end

  describe BonidNotifier, ".notify_consent_change" do
    it "records the revocation as undeliverable instead of silently skipping" do
      expect(Net::HTTP).not_to receive(:start)
      grant = revoked_grant

      expect {
        BonidNotifier.notify_consent_change(grant, "consent.revoked")
      }.to change(ApiWebhookEvent, :count).by(1)
        .and change { PartnerAuditLog.where(event: "consent_revoked_undeliverable").count }.by(1)

      event = ApiWebhookEvent.last
      expect(event.status).to eq("undeliverable")
      expect(event.payload["undeliverable_reason"]).to eq("no_webhook_url")
      expect(event.payload["consent_id"]).to eq(grant.id)
    end

    it "holds events (never sends unsigned) when the partner has a URL but no signing secret" do
      partner.update_columns(webhook_url: "https://partner.example.com/hook", webhook_secret: nil)
      expect(Net::HTTP).not_to receive(:start)

      event = BonidNotifier.notify_consent_change(revoked_grant, "consent.revoked")

      expect(event.status).to eq("undeliverable")
      expect(event.payload["undeliverable_reason"]).to eq("no_webhook_secret")
    end

    it "reuses the same event record on retry instead of creating duplicates" do
      partner.update!(webhook_url: "https://partner.example.com/hook")
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
      grant = revoked_grant

      BonidNotifier.notify_consent_change(grant, "consent.revoked", attempt: 1)
      event = ApiWebhookEvent.where(event_type: "consent.revoked").last

      expect {
        BonidNotifier.notify_consent_change(grant, "consent.revoked", attempt: 2, webhook_event: event)
      }.not_to change(ApiWebhookEvent, :count)
      expect(event.reload.retry_attempts).to eq(2)
    end
  end

  describe Partner do
    it "queues the backlog as soon as a webhook URL is saved" do
      partner # create
      expect {
        partner.update!(webhook_url: "https://partner.example.com/hook")
      }.to have_enqueued_job(PartnerWebhookBacklogJob).with(partner.id)
    end

    it "does not queue the backlog when a URL is saved but there is no signing secret" do
      partner.update_columns(webhook_secret: nil)
      expect {
        partner.update!(webhook_url: "https://partner.example.com/hook")
      }.not_to have_enqueued_job(PartnerWebhookBacklogJob)
    end

    it "queues the backlog once a signing secret is created" do
      partner.update_columns(webhook_url: "https://partner.example.com/hook", webhook_secret: nil)
      expect {
        partner.generate_webhook_secret!
      }.to have_enqueued_job(PartnerWebhookBacklogJob).with(partner.id)
    end

    it "does not queue the backlog for an unverified partner" do
      unverified = create(:partner, verified_at: nil, webhook_url: nil)
      expect {
        unverified.update!(webhook_url: "https://partner.example.com/hook")
      }.not_to have_enqueued_job(PartnerWebhookBacklogJob)
    end

    it "allows http://localhost outside production but still requires HTTPS elsewhere" do
      partner.webhook_url = "http://localhost:3000/bonid_revocation_webhook"
      expect(partner).to be_valid

      partner.webhook_url = "http://partner.example.com/hook"
      expect(partner).not_to be_valid
      expect(partner.errors[:webhook_url]).to include("must be HTTPS")
    end
  end

  describe PartnerWebhookBacklogJob do
    it "delivers the latest held event per consent and supersedes older ones" do
      grant = revoked_grant
      older = BonidNotifier.notify_consent_change(grant, "consent.approved")
      newer = BonidNotifier.notify_consent_change(grant, "consent.revoked")
      expect([ older.status, newer.status ]).to all(eq("undeliverable"))

      partner.update_columns(webhook_url: "https://partner.example.com/hook")
      allow(Net::HTTP).to receive(:start).and_return(ok_response)

      described_class.perform_now(partner.id)

      expect(newer.reload.status).to eq("delivered")
      expect(older.reload.status).to eq("superseded")
      expect(Net::HTTP).to have_received(:start).once
    end

    it "does nothing while the partner still has no webhook URL" do
      held = BonidNotifier.notify_consent_change(revoked_grant, "consent.revoked")
      expect(Net::HTTP).not_to receive(:start)

      described_class.perform_now(partner.id)
      expect(held.reload.status).to eq("undeliverable")
    end
  end

  describe WebhookBacklogSweepJob do
    it "queues a backlog job for each reachable partner with held events" do
      BonidNotifier.notify_consent_change(revoked_grant, "consent.revoked")
      partner.update_columns(webhook_url: "https://partner.example.com/hook")

      expect { described_class.perform_now }
        .to have_enqueued_job(PartnerWebhookBacklogJob).with(partner.id)
    end
  end
end
