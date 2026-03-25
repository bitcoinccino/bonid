# frozen_string_literal: true

class BillingMailerPreview < ActionMailer::Preview
  # Preview: /rails/mailers/billing_mailer/credit_receipt
  def credit_receipt
    partner = Partner.find_by(slug: "coinbase") || Partner.first
    payment = partner.partner_payments.last || mock_payment(partner)
    Partners::BillingMailer.credit_receipt(partner, payment, 10_000, partner.credit_balance)
  end

  # Preview: /rails/mailers/billing_mailer/low_balance_alert
  def low_balance_alert
    partner = Partner.find_by(slug: "coinbase") || Partner.first
    Partners::BillingMailer.low_balance_alert(partner)
  end

  # Preview: /rails/mailers/billing_mailer/payment_confirmation
  def payment_confirmation
    partner = Partner.first
    payment = partner.partner_payments.last || mock_payment(partner)
    Partners::BillingMailer.payment_confirmation(partner, payment)
  end

  private

  def mock_payment(partner)
    PartnerPayment.new(
      partner: partner,
      partner_plan: partner.partner_plan,
      payment_method: "moncash",
      amount: 15_000,
      currency: "HTG",
      status: "completed",
      payment_type: "top_up",
      order_id: "BONID-TEST-20260319",
      transaction_id: "MC-123456",
      credits: 10_000
    )
  end
end
