# frozen_string_literal: true

# Launch switch for the citizen wallet's profile cards stacked behind the
# BonID card — turned on one card at a time.
#
#   WALLET_PROFILE_CARDS=                   → BonID card only (v1 launch)
#   WALLET_PROFILE_CARDS=emergency          → + Emergency contacts
#   WALLET_PROFILE_CARDS=emergency,health   → + Health
#   WALLET_PROFILE_CARDS=all                → every card
#
# Card keys: health bank emergency family social physical.
#
# Hidden cards keep their stored data, so partner scopes, emergency-contact
# alerts and family-link confirmations keep working with whatever citizens
# already entered.
module WalletProfileCardsPausable
  # Stack order: first = closest to the BonID card, last = top of the stack.
  CARDS = %w[health bank emergency family social physical].freeze

  def self.enabled_cards
    raw = ENV.fetch("WALLET_PROFILE_CARDS", "").to_s.downcase
    requested = raw.split(/[\s,]+/).reject(&:empty?)
    return CARDS if requested.include?("all")

    unknown = requested - CARDS
    Rails.logger.warn("[WalletProfileCards] Unknown card(s) in WALLET_PROFILE_CARDS: #{unknown.join(', ')}") if unknown.any?

    CARDS & requested # keep stack order, drop unknowns
  end

  def self.enabled?(card)
    enabled_cards.include?(card.to_s)
  end
end
