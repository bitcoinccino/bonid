# frozen_string_literal: true

# Fetches the daily USD/HTG exchange rate.
# Scheduled via config/recurring.yml to run once per day.
class RefreshExchangeRateJob < ApplicationJob
  queue_as :default

  def perform
    ExchangeRateService.new.refresh!
  end
end
