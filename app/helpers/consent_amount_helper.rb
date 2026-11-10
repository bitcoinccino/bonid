# frozen_string_literal: true

# Formats a transaction consent amount for the citizen approval screens.
# The citizen approves based on this text, so it must show the real
# currency and enough decimals (0.002 BTC must never render as "$ 0").
module ConsentAmountHelper
  FIAT_SYMBOLS = { "HTG" => "G", "USD" => "$", "CAD" => "CA$", "EUR" => "€", "DOP" => "RD$" }.freeze

  def consent_amount_display(amount, currency)
    return if amount.blank?

    code = currency.to_s.upcase.presence || "HTG"

    if TransactionConsent::CRYPTO_CURRENCIES.include?(code)
      # Up to 8 decimals, trailing zeros trimmed: "0.002 BTC", "1.5 ETH"
      number = number_with_precision(amount, precision: TransactionConsent::CRYPTO_DECIMALS,
                                             strip_insignificant_zeros: true, delimiter: ",")
      "#{number} #{code}"
    elsif code == "HTG"
      "#{number_with_precision(amount, precision: 0, delimiter: ',')} G"
    else
      symbol = FIAT_SYMBOLS.fetch(code, "")
      number = number_with_precision(amount, precision: 2, strip_insignificant_zeros: amount.to_d.frac.zero?, delimiter: ",")
      "#{symbol}#{number} #{code}".strip
    end
  end
end
