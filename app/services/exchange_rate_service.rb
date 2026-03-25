# frozen_string_literal: true

require "net/http"
require "json"

# ExchangeRateService
#
# Fetches the daily USD/HTG exchange rate and stores it in the CurrencyRate table.
# Primary source: BRH (Banque de la République d'Haïti) or fallback API.
#
# Usage:
#   ExchangeRateService.new.refresh!
#   CurrencyRate.current  # → latest rate with buffer
#
class ExchangeRateService
  FALLBACK_RATE = 150.0  # Safety net if all sources fail
  DEFAULT_BUFFER = 5.0   # 5% buffer for volatility protection

  def initialize(buffer_percentage: nil)
    @buffer = buffer_percentage || current_buffer || DEFAULT_BUFFER
  end

  # Fetch latest rate and save to DB
  def refresh!
    rate = fetch_rate_from_api

    if rate && rate > 0
      CurrencyRate.create!(
        from_currency: "USD",
        to_currency: "HTG",
        rate: rate,
        buffer_percentage: @buffer,
        source: @source || "api",
        fetched_at: Time.current
      )

      # Bust cache
      Rails.cache.delete("currency_rate:USD:HTG")

      Rails.logger.info("[ExchangeRate] USD/HTG updated: #{rate} (effective: #{rate * (1 + @buffer / 100)})")
      rate
    else
      Rails.logger.warn("[ExchangeRate] Failed to fetch rate. Using latest from DB.")
      nil
    end
  end

  # Current effective rate (with buffer)
  def current_rate
    CurrencyRate.current(from: "USD", to: "HTG")&.effective_rate || FALLBACK_RATE
  end

  private

  # Try multiple sources for USD/HTG rate
  def fetch_rate_from_api
    rate = fetch_from_exchangerate_api
    return rate if rate

    rate = fetch_from_open_exchange_rates
    return rate if rate

    Rails.logger.warn("[ExchangeRate] All API sources failed")
    nil
  end

  # Source 1: ExchangeRate-API (free tier, no key needed)
  def fetch_from_exchangerate_api
    @source = "exchangerate-api"
    uri = URI("https://open.er-api.com/v6/latest/USD")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    response = http.request(Net::HTTP::Get.new(uri))
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data.dig("rates", "HTG")&.to_f
  rescue => e
    Rails.logger.warn("[ExchangeRate] exchangerate-api failed: #{e.message}")
    nil
  end

  # Source 2: Open Exchange Rates (requires app_id in ENV)
  def fetch_from_open_exchange_rates
    app_id = ENV["OPEN_EXCHANGE_RATES_APP_ID"]
    return nil if app_id.blank?

    @source = "open_exchange_rates"
    uri = URI("https://openexchangerates.org/api/latest.json?app_id=#{app_id}&symbols=HTG")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10

    response = http.request(Net::HTTP::Get.new(uri))
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data.dig("rates", "HTG")&.to_f
  rescue => e
    Rails.logger.warn("[ExchangeRate] open_exchange_rates failed: #{e.message}")
    nil
  end

  # Get the current buffer from the latest rate record (admin may have changed it)
  def current_buffer
    CurrencyRate.where(from_currency: "USD", to_currency: "HTG")
                .order(created_at: :desc).first&.buffer_percentage
  end
end
