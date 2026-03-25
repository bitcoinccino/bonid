# frozen_string_literal: true

# app/controllers/partner_portal/credits_controller.rb
#
# Prepaid credit wallet for partners.
# Like recharging a Natcom/Digicel phone — buy credits, use them for API calls.
#
# 1 Credit = $1.00 USD
#
# Top-up packages:
#   +50 Credits   = $50  (≈ 7,500 HTG)
#   +100 Credits  = $100 (≈ 15,000 HTG)
#   +500 Credits  = $500 (≈ 75,000 HTG)
#   +Custom
#
class PartnerPortal::CreditsController < PartnerPortal::BaseController
  before_action :require_partner_admin!, only: [:top_up, :reconcile]

  # ============================================================
  # GET /partner_portal/credits
  # "Gas Gauge" wallet dashboard
  # ============================================================
  def show
    @partner = @current_partner
    @balance = @partner.credit_balance
    @purchasing_power = @partner.credit_purchasing_power

    # Exchange rate for HTG pricing
    @rate = CurrencyRate.current(from: "USD", to: "HTG")
    @htg_rate = @rate&.effective_rate || 150.0

    # Top-up packages with dynamic HTG pricing
    @packages = top_up_packages

    # Combined activity feed (top-ups + deductions, chronological)
    @activity = @partner.credit_ledger_entries.recent.limit(50)

    # Usage stats
    @stats = {
      credits_used_today: @partner.credit_ledger_entries.deductions.today.sum(:amount).abs,
      credits_used_this_month: @partner.credits_used_this_month,
      credits_added_this_month: @partner.credits_added_this_month,
      top_api_calls: @partner.credit_ledger_entries.deductions.this_month
                            .group(:endpoint_key).sum(:amount)
                            .transform_values(&:abs)
                            .sort_by { |_, v| -v }.first(5)
    }

    # Pending MonCash payments (for reconciliation)
    @pending_payments = @partner.partner_payments
                               .where(payment_method: "moncash", status: "pending")
                               .where("created_at > ?", 24.hours.ago)
                               .order(created_at: :desc)
  end

  # ============================================================
  # POST /partner_portal/credits/top_up
  # Initiates a credit purchase via MonCash or Stripe
  # ============================================================
  def top_up
    partner = current_partner_admin.partner
    credits = BigDecimal(params[:credits].to_s)
    payment_method = params[:payment_method].to_s.downcase

    # Validate credit amount ($10 min, $10,000 max)
    unless credits >= BigDecimal("10") && credits <= BigDecimal("10000")
      redirect_to partner_portal_credits_path, alert: "Chwazi yon kantite kredi ant $10 ak $10,000."
      return
    end

    usd_amount = credits.round(2) # 1 credit = $1.00

    case payment_method
    when "moncash"
      top_up_moncash(partner, credits, usd_amount)
    when "stripe"
      top_up_stripe(partner, credits, usd_amount)
    else
      redirect_to partner_portal_credits_path, alert: "Chwazi yon metòd peman (MonCash oswa Stripe)."
    end
  end

  # ============================================================
  # POST /partner_portal/credits/reconcile
  # Manual MonCash reconciliation — "I paid but didn't get credits"
  # ============================================================
  def reconcile
    partner = current_partner_admin.partner
    order_id = params[:order_id].to_s.strip

    payment = partner.partner_payments.find_by(order_id: order_id, status: "pending", payment_method: "moncash")

    unless payment
      redirect_to partner_portal_credits_path, alert: "Pa jwenn peman sa a oswa li deja konplete."
      return
    end

    # Rate limit: max 3 attempts
    if payment.reconciliation_attempts.to_i >= 3
      redirect_to partner_portal_credits_path, alert: "Limit rekonsiliasyon atenn. Kontakte sipò."
      return
    end

    begin
      service = MoncashPaymentService.new
      result = service.verify_payment(order_id: order_id)

      payment.update!(
        reconciliation_attempts: payment.reconciliation_attempts.to_i + 1,
        reconciled_at: result[:success] ? Time.current : nil,
        reconciled_by: result[:success] ? "partner" : nil
      )

      if result[:success]
        # Credits were added by MoncashPaymentService#activate_credit_top_up
        redirect_to partner_portal_credits_path, notice: "Peman verifye! Kredi yo ajoute nan kont ou."
      else
        redirect_to partner_portal_credits_path, alert: "MonCash pa konfime peman sa a ankò. Eseye ankò pita."
      end
    rescue MoncashPaymentService::PaymentError => e
      payment.update!(
        reconciliation_attempts: payment.reconciliation_attempts.to_i + 1,
        last_reconciliation_error: e.message
      )
      redirect_to partner_portal_credits_path, alert: "Erè rekonsiliasyon: #{e.message}"
    end
  end

  private

  # ============================================================
  # TOP-UP PACKAGES
  # Dynamic HTG pricing from CurrencyRate
  # ============================================================
  def top_up_packages
    rate = CurrencyRate.current(from: "USD", to: "HTG")
    htg_rate = rate&.effective_rate || 150.0

    [
      { credits: BigDecimal("50"),  usd: 50,  htg: (50 * htg_rate).round(0) },
      { credits: BigDecimal("100"), usd: 100, htg: (100 * htg_rate).round(0) },
      { credits: BigDecimal("500"), usd: 500, htg: (500 * htg_rate).round(0) }
    ]
  end

  # ============================================================
  # MonCash Top-Up
  # ============================================================
  def top_up_moncash(partner, credits, usd_amount)
    rate = CurrencyRate.current(from: "USD", to: "HTG")
    htg_amount = rate ? (usd_amount * rate.effective_rate).round(2) : (usd_amount * 150.0).round(2)

    payment = PartnerPayment.create!(
      partner: partner,
      payment_method: "moncash",
      amount: htg_amount,
      currency: "HTG",
      status: "pending",
      payment_type: "top_up",
      metadata: {
        credits: credits,
        usd_amount: usd_amount,
        exchange_rate: rate&.effective_rate,
        initiated_at: Time.current.iso8601
      }
    )

    service = MoncashPaymentService.new
    result = service.create_payment_for_credits(partner: partner, payment: payment, amount_htg: htg_amount)

    redirect_to result[:redirect_url], allow_other_host: true
  rescue MoncashPaymentService::PaymentError => e
    Rails.logger.error("[Credits#top_up_moncash] #{e.message}")
    redirect_to partner_portal_credits_path, alert: "MonCash pa disponib pou kounye a. Tanpri itilize Stripe oswa eseye ankò pita."
  end


  # ============================================================
  # Stripe Top-Up
  # ============================================================
  def top_up_stripe(partner, credits, usd_amount)
    stripe_customer_id = partner.stripe_customer_id || create_stripe_customer!(partner)

    session = Stripe::Checkout::Session.create(
      customer: stripe_customer_id,
      payment_method_types: ["card"],
      line_items: [{
        price_data: {
          currency: "usd",
          unit_amount: (usd_amount * 100).to_i,
          product_data: {
            name: "BonID Credits",
            description: "#{credits.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} Credits"
          }
        },
        quantity: 1
      }],
      mode: "payment",
      success_url: partner_portal_credits_url(success: true, credits: credits),
      cancel_url: partner_portal_credits_url(cancel: true),
      metadata: { partner_id: partner.id, credits: credits, type: "credit_top_up" }
    )

    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error("[Credits#top_up_stripe] Stripe error: #{e.message}")
    redirect_to partner_portal_credits_path, alert: "Erè Stripe: #{e.message}"
  end

  def create_stripe_customer!(partner)
    admin = partner.partner_admin_user
    customer = Stripe::Customer.create(
      email: admin&.email || partner.email,
      name: partner.name,
      metadata: { partner_id: partner.id, partner_slug: partner.slug }
    )
    partner.update!(stripe_customer_id: customer.id)
    customer.id
  end

  def require_partner_admin!
    unless partner_admin_signed_in?
      redirect_to new_partner_admin_session_path(return_to: request.fullpath),
                  alert: "Ou dwe konekte kòm Admin Patnè."
    end
  end

  def current_partner_admin
    warden.authenticate(scope: :partner_admin)
  end

  def partner_admin_signed_in?
    !!current_partner_admin
  end
end
