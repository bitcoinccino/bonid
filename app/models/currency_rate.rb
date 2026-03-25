# frozen_string_literal: true

# CurrencyRate
#
# Tracks daily USD/HTG exchange rate with admin-configurable buffer.
# Used at checkout time to convert credit top-up amounts.
#
# 1 Credit = $0.01 USD
# At rate 150 HTG/USD: 1 Credit ≈ 1.50 HTG
# With 5% buffer:      1 Credit ≈ 1.575 HTG (partner pays slightly more for volatility protection)
#
class CurrencyRate < ApplicationRecord
  validates :rate, presence: true, numericality: { greater_than: 0 }
  validates :from_currency, :to_currency, presence: true
  validates :buffer_percentage, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 25 }

  before_save :compute_effective_rate

  scope :latest, -> { order(created_at: :desc) }

  # ============================================================
  # CLASS METHODS
  # ============================================================

  # Returns the current USD → HTG rate (cached 1 hour)
  def self.current(from: "USD", to: "HTG")
    Rails.cache.fetch("currency_rate:#{from}:#{to}", expires_in: 1.hour) do
      where(from_currency: from, to_currency: to).latest.first
    end
  end

  # Convert amount between currencies using effective rate
  # convert(100, from: "USD", to: "HTG") → 15750.0 (with buffer)
  def self.convert(amount, from: "USD", to: "HTG")
    rate_record = current(from: from, to: to)
    return nil unless rate_record

    (amount.to_f * rate_record.effective_rate.to_f).round(2)
  end

  # Convert credits to HTG for top-up pricing
  # credits_to_htg(50) → 7875.0 (50 credits × $1.00 × 157.5 effective rate)
  # 1 credit = $1.00 USD
  def self.credits_to_htg(credit_count)
    convert(credit_count.to_d, from: "USD", to: "HTG")
  end

  # How many credits does X HTG buy?
  # 1 credit = $1.00 USD
  def self.htg_to_credits(htg_amount)
    rate_record = current(from: "USD", to: "HTG")
    return nil unless rate_record

    usd_equivalent = BigDecimal(htg_amount.to_s) / BigDecimal(rate_record.effective_rate.to_s)
    usd_equivalent.round(2) # 1 credit = $1.00, so USD = credits
  end

  private

  def compute_effective_rate
    self.effective_rate = rate * (1 + (buffer_percentage.to_f / 100))
  end
end
