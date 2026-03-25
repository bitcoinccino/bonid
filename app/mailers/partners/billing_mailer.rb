# frozen_string_literal: true

# app/mailers/partners/billing_mailer.rb
#
# Billing emails for credit-based partner billing.
# Messages in Haitian Creole (primary audience is Haitian businesses).
#
module Partners
  class BillingMailer < ApplicationMailer
    layout "mailer"
    default from: "BonID Billing <billing@verifyem.ht>"

    # ============================================================
    # CREDIT TOP-UP RECEIPT
    # Sent after every successful credit purchase.
    # Shows: credits added, new balance, payment details, rate card.
    # ============================================================
    def credit_receipt(partner, payment, credits, new_balance)
      @partner = partner
      @payment = payment
      @credits = credits
      @new_balance = new_balance
      @usd_amount = credits.to_d.round(2) # 1 credit = $1.00
      @wallet_url = partner_portal_credits_url
      @receipt_date = Time.current

      @email_product = "bonid"
      @email_badge = "RESI"

      mail(
        to: partner.email,
        subject: "BonID: Resi — +$#{'%.2f' % credits} Credits ajoute"
      )
    end

    # Low balance alert (sent when balance drops below threshold)
    def low_balance_alert(partner)
      @partner = partner
      @balance = partner.credit_balance
      @purchasing_power = partner.credit_purchasing_power
      @wallet_url = partner_portal_credits_url

      # Unified email layout config
      @email_product = "bonid"
      @email_badge = "PARTNER BILLING"
      @email_alert = "Alèt Balans Ba — Aksyon Nesesè"
      @email_alert_type = "danger"

      mail(
        to: partner.email,
        subject: "BonID: Balans ba — #{@balance} Credits rete"
      )
    end

    private

    def number_with_delimiter(number)
      number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end
end
