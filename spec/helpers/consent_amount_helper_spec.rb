# frozen_string_literal: true

require "rails_helper"

# The citizen approves a transaction based on this text, so a wrong
# currency or a rounded-away amount is a security problem, not cosmetics.
RSpec.describe ConsentAmountHelper, type: :helper do
  it "shows gourdes without decimals" do
    expect(helper.consent_amount_display(BigDecimal("25000"), "HTG")).to eq("25,000 G")
  end

  it "shows dollars with their symbol and code" do
    expect(helper.consent_amount_display(BigDecimal("1250.5"), "USD")).to eq("$1,250.50 USD")
    expect(helper.consent_amount_display(BigDecimal("100"), "USD")).to eq("$100 USD")
  end

  it "never shows euros or pesos as dollars" do
    expect(helper.consent_amount_display(BigDecimal("100"), "EUR")).to eq("€100 EUR")
    expect(helper.consent_amount_display(BigDecimal("100"), "DOP")).to eq("RD$100 DOP")
  end

  it "shows small crypto amounts exactly (never \"$ 0\")" do
    expect(helper.consent_amount_display(BigDecimal("0.002"), "BTC")).to eq("0.002 BTC")
    expect(helper.consent_amount_display(BigDecimal("0.00000001"), "BTC")).to eq("0.00000001 BTC")
  end

  it "returns nil when there's no amount" do
    expect(helper.consent_amount_display(nil, "HTG")).to be_nil
  end
end
