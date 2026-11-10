# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionConsent, "security windows", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:partner) { create(:partner, :approved) }
  let(:citizen) { create(:user) }

  def build_consent(type, **attrs)
    described_class.create!(citizen: citizen, partner: partner, transaction_type: type, scopes: %w[profile], **attrs)
  end

  describe "time to answer (TTL)" do
    it "gives crypto exchange onboarding 15 minutes, not 30" do
      freeze_time do
        expect(build_consent("crypto_kyc").expires_at).to eq(15.minutes.from_now)
      end
    end

    it "keeps money movement at 5 minutes" do
      freeze_time do
        expect(build_consent("wire_transfer").expires_at).to eq(5.minutes.from_now)
      end
    end

    it "has no type longer than 15 minutes" do
      expect(described_class::TTL_BY_TYPE.values.max).to eq(15.minutes)
    end
  end

  describe "data access window after approval" do
    it "defaults to 10 minutes" do
      expect(build_consent("kyc_check").data_access_window).to eq(10.minutes)
    end

    it "still honors a per-consent override" do
      expect(build_consent("kyc_check", data_access_window_minutes: 3).data_access_window).to eq(3.minutes)
    end

    it "allows access inside the window and refuses it after" do
      consent = build_consent("kyc_check")
      consent.update_columns(status: described_class.statuses[:approved], decided_at: Time.current)

      travel_to(9.minutes.from_now) { expect(consent.data_access_allowed?).to be(true) }
      travel_to(11.minutes.from_now) { expect(consent.data_access_allowed?).to be(false) }
    end
  end

  describe "one-time use for money movement" do
    it "turns burn-after-read on for every money-moving type" do
      described_class::MONEY_MOVEMENT_TYPES.each do |type|
        expect(build_consent(type).burn_after_read).to be(true), "#{type} should be one-time use"
      end
    end

    it "can't be switched off by the partner for money types" do
      expect(build_consent("wire_transfer", burn_after_read: false).burn_after_read).to be(true)
    end

    it "leaves identity-only types reusable within the window" do
      expect(build_consent("kyc_check").burn_after_read).to be(false)
    end

    it "only lists types the model accepts" do
      expect(described_class::MONEY_MOVEMENT_TYPES - described_class::VALID_TRANSACTION_TYPES).to be_empty
    end
  end

  describe "#claim_single_read!" do
    let(:consent) do
      build_consent("wire_transfer").tap do |c|
        c.update_columns(status: described_class.statuses[:approved], decided_at: Time.current)
      end
    end

    it "lets exactly one read through" do
      expect(consent.claim_single_read!).to be(true)
      expect(consent.data_access_count).to eq(1)
      expect(consent.data_access_allowed?).to be(false)
    end

    it "refuses a second claim even from a stale copy loaded before the first read" do
      stale_copy = described_class.find(consent.id) # loaded while count was still 0
      expect(consent.claim_single_read!).to be(true)
      expect(stale_copy.claim_single_read!).to be(false)
      expect(consent.reload.data_access_count).to eq(1)
    end
  end

  describe "background audit job" do
    let(:consent) do
      build_consent("wire_transfer").tap do |c|
        c.update_columns(status: described_class.statuses[:approved], decided_at: Time.current)
      end
    end

    it "doesn't double count a read already claimed synchronously" do
      consent.claim_single_read!
      RecordConsentDataAccessJob.perform_now(consent_id: consent.id, ip: "127.0.0.1", scopes_used: %w[profile], counted: true)
      expect(consent.reload.data_access_count).to eq(1)
    end

    it "still counts reads for reusable consents" do
      reusable = build_consent("kyc_check")
      RecordConsentDataAccessJob.perform_now(consent_id: reusable.id, ip: "127.0.0.1", scopes_used: %w[profile])
      expect(reusable.reload.data_access_count).to eq(1)
    end
  end
end
