# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletProfileCardsPausable do
  def with_env(value)
    original = ENV["WALLET_PROFILE_CARDS"]
    value.nil? ? ENV.delete("WALLET_PROFILE_CARDS") : ENV["WALLET_PROFILE_CARDS"] = value
    yield
  ensure
    original.nil? ? ENV.delete("WALLET_PROFILE_CARDS") : ENV["WALLET_PROFILE_CARDS"] = original
  end

  it "shows no profile cards by default (BonID only)" do
    with_env(nil) { expect(described_class.enabled_cards).to eq([]) }
    with_env("")  { expect(described_class.enabled_cards).to eq([]) }
  end

  it "enables cards one by one, in stack order regardless of how they're listed" do
    with_env("health, emergency") do
      expect(described_class.enabled_cards).to eq(%w[health emergency])
      expect(described_class.enabled?(:emergency)).to be true
      expect(described_class.enabled?(:bank)).to be false
    end
  end

  it "accepts 'all'" do
    with_env("all") { expect(described_class.enabled_cards).to eq(described_class::CARDS) }
  end

  it "ignores unknown card names" do
    with_env("emergency,passport") { expect(described_class.enabled_cards).to eq(%w[emergency]) }
  end
end
