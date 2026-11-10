# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionConsent, "currency and amount validation", type: :model do
  let(:partner) { create(:partner, :approved) }
  let(:citizen) { create(:user, :identity_verified) }

  def consent(type: "wire_transfer", **attrs)
    described_class.new(citizen: citizen, partner: partner, transaction_type: type, scopes: %w[profile], **attrs)
  end

  describe "currency" do
    it "defaults to HTG when blank" do
      c = consent(currency: "")
      expect(c).to be_valid
      expect(c.currency).to eq("HTG")
    end

    it "normalizes case and spaces" do
      c = consent(currency: " usd ")
      c.valid?
      expect(c.currency).to eq("USD")
    end

    it "accepts every supported fiat currency on any type" do
      described_class::FIAT_CURRENCIES.each do |code|
        expect(consent(currency: code, amount: 100)).to be_valid, "#{code} should be accepted"
      end
    end

    it "rejects unknown currencies with a helpful message" do
      c = consent(currency: "XYZ", amount: 100)
      expect(c).not_to be_valid
      expect(c.errors[:currency].first).to include("not supported").and include("HTG")
    end

    it "accepts crypto on crypto types" do
      expect(consent(type: "crypto_sell", currency: "BTC", amount: "0.002")).to be_valid
    end

    it "rejects crypto on non-crypto types" do
      c = consent(type: "wire_transfer", currency: "BTC", amount: 1)
      expect(c).not_to be_valid
      expect(c.errors[:currency].first).to include("only allowed on crypto")
    end
  end

  describe "amount" do
    it "is optional" do
      expect(consent(amount: nil)).to be_valid
    end

    it "must be positive" do
      expect(consent(amount: 0)).not_to be_valid
      expect(consent(amount: -5)).not_to be_valid
    end

    it "allows cents but not fractions of a cent for fiat" do
      expect(consent(currency: "USD", amount: "10.25")).to be_valid
      expect(consent(currency: "USD", amount: "10.255")).not_to be_valid
    end

    it "allows satoshi precision (8 decimals) for crypto, not more" do
      expect(consent(type: "crypto_transfer", currency: "BTC", amount: "0.00000001")).to be_valid
      expect(consent(type: "crypto_transfer", currency: "BTC", amount: "0.000000001")).not_to be_valid
    end

    it "stores a tiny crypto amount without rounding it to zero" do
      saved = consent(type: "crypto_sell", currency: "BTC", amount: "0.002").tap(&:save!)
      expect(saved.reload.amount).to eq(BigDecimal("0.002"))
    end
  end
end
