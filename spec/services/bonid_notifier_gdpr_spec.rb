# frozen_string_literal: true

require "rails_helper"

RSpec.describe BonidNotifier, "GDPR webhook retries" do
  let(:partner) { create(:partner, :approved, webhook_url: "https://example.com/webhook", webhook_secret: SecureRandom.hex(16)) }
  let(:citizen) { create(:user) }
  let(:grant) do
    ConsentGrant.create!(
      citizen: citizen,
      partner: partner,
      requested_scopes: %w[openid profile],
      granted_scopes: %w[openid profile],
      status: :revoked,
      granted_at: 1.day.ago,
      revoked_at: Time.current,
      change_reason: "citizen_revoked",
      expires_at: 89.days.from_now
    )
  end

  before do
    # Stub HTTP to simulate failure
    allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
  end

  describe "consent.revoked retry schedule" do
    it "uses GDPR_MAX_RETRIES (10) for consent.revoked events" do
      expect(described_class::GDPR_MAX_RETRIES).to eq(10)
    end

    it "has an escalating retry schedule" do
      schedule = described_class::GDPR_RETRY_SCHEDULE
      expect(schedule.size).to eq(9) # attempts 2-10
      expect(schedule.first).to eq(5.seconds)
      expect(schedule.last).to eq(12.hours)
    end

    it "enqueues retry job on first failure for consent.revoked" do
      expect {
        described_class.notify_consent_change(grant, "consent.revoked", attempt: 1)
      }.to have_enqueued_job(WebhookRetryJob)
    end

    it "creates a dead_letter status after max retries" do
      # Pre-create the webhook event as if it was created on attempt 1
      webhook_event = ApiWebhookEvent.create!(
        partner: partner,
        event_type: "consent.revoked",
        bonid: citizen.bonid,
        payload: { event: "consent.revoked", consent_id: grant.id },
        retry_attempts: 9,
        direction: "outbound",
        status: "failed"
      )

      # Simulate the 10th attempt (final) by calling with attempt = GDPR_MAX_RETRIES
      # This should NOT enqueue another retry and should mark as dead_letter
      described_class.notify_consent_change(grant, "consent.revoked", attempt: 10)

      # The new webhook event created in this call should be dead_letter
      latest = ApiWebhookEvent.where(event_type: "consent.revoked").order(created_at: :desc).first
      expect(latest.status).to eq("dead_letter")
    end

    it "creates admin audit log on dead letter for GDPR events" do
      described_class.notify_consent_change(grant, "consent.revoked", attempt: 10)

      log = PartnerAuditLog.find_by(event: "gdpr_erasure_delivery_failed")
      expect(log).to be_present
      expect(log.details).to include("Manual follow-up required")
    end
  end

  describe "non-GDPR events" do
    it "uses standard MAX_RETRIES (3) for consent.approved" do
      grant.update_column(:status, "approved")

      # After attempt 3, no more retries
      expect {
        described_class.notify_consent_change(grant, "consent.approved", attempt: 3)
      }.not_to have_enqueued_job(WebhookRetryJob)
    end
  end

  describe "data_erasure payload" do
    before do
      # Let HTTP succeed for this test
      allow(Net::HTTP).to receive(:start).and_return(
        instance_double(Net::HTTPResponse, is_a?: true, code: "200", body: "ok")
      )
    end

    it "includes GDPR Article 17 erasure request for consent.revoked" do
      # Capture the payload sent
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_opts, &block|
        http = instance_double(Net::HTTP, open_timeout: nil, read_timeout: nil)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request) do |req|
          payload = JSON.parse(req.body)
          expect(payload["data_erasure"]).to be_present
          expect(payload["data_erasure"]["requested"]).to be true
          expect(payload["data_erasure"]["gdpr_article"]).to include("Article 17")
          expect(payload["data_erasure"]["deadline"]).to be_present

          response = instance_double(Net::HTTPSuccess, code: "200", body: "ok")
          allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
          response
        end
        block.call(http)
      end

      described_class.notify_consent_change(grant, "consent.revoked", attempt: 1)
    end
  end
end
