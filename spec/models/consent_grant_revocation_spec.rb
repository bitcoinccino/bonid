# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsentGrant, "revocation" do
  let(:partner) { create(:partner, :approved, webhook_url: "https://example.com/webhook", webhook_secret: SecureRandom.hex(16)) }
  let(:citizen) { create(:user) }
  let(:grant) do
    ConsentGrant.create!(
      citizen: citizen,
      partner: partner,
      requested_scopes: %w[openid profile email],
      granted_scopes: %w[openid profile email],
      status: :approved,
      granted_at: Time.current,
      expires_at: 90.days.from_now
    )
  end

  # ─────────────────────────────────────────────────────────
  # Token invalidation on revoke
  # ─────────────────────────────────────────────────────────
  describe "#revoke! token invalidation" do
    it "revokes all active access tokens for the citizen + partner" do
      token1 = OauthAccessToken.create!(partner: partner, citizen: citizen, scopes: %w[openid], expires_at: 1.hour.from_now)
      token2 = OauthAccessToken.create!(partner: partner, citizen: citizen, scopes: %w[profile], expires_at: 2.hours.from_now)
      # Already expired — should not be touched
      expired = OauthAccessToken.create!(partner: partner, citizen: citizen, scopes: %w[email], expires_at: 1.hour.ago)

      grant.revoke!(reason: "citizen_request")

      expect(token1.reload.revoked_at).to be_present
      expect(token2.reload.revoked_at).to be_present
      expect(expired.reload.revoked_at).to be_nil # already expired, not touched
    end

    it "does not revoke tokens for other partners" do
      other_partner = create(:partner, :approved)
      other_token = OauthAccessToken.create!(partner: other_partner, citizen: citizen, scopes: %w[openid], expires_at: 1.hour.from_now)

      grant.revoke!(reason: "test")

      expect(other_token.reload.revoked_at).to be_nil
    end

    it "fires the consent webhook job" do
      expect {
        grant.revoke!(reason: "citizen_request")
      }.to have_enqueued_job(ConsentWebhookJob).with(grant.id, "consent.revoked")
    end

    it "creates a partner audit log with token count" do
      OauthAccessToken.create!(partner: partner, citizen: citizen, scopes: %w[openid], expires_at: 1.hour.from_now)

      grant.revoke!(reason: "test")

      log = PartnerAuditLog.last
      expect(log.event).to eq("consent_revoked")
      expect(log.metadata["tokens_revoked"]).to eq(1)
    end
  end

  # ─────────────────────────────────────────────────────────
  # Grant status after revoke
  # ─────────────────────────────────────────────────────────
  describe "#revoke! status" do
    it "sets status to revoked" do
      grant.revoke!(reason: "citizen_request")

      expect(grant.reload.status).to eq("revoked")
      expect(grant.revoked_at).to be_present
      expect(grant).not_to be_active
    end
  end
end
