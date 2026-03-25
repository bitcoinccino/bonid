# frozen_string_literal: true

# app/controllers/partner_portal/billing_controller.rb
class PartnerPortal::BillingController < PartnerPortal::BaseController
  # GET /partner_portal/billing
  def show
    @partner = @current_partner
    @payments = @partner&.partner_payments&.recent&.limit(50) || []

    # Filter support
    if params[:status].present? && %w[completed pending failed refunded].include?(params[:status])
      @payments = @partner.partner_payments.where(status: params[:status]).order(created_at: :desc).limit(50)
      @active_filter = params[:status]
    end

    if params[:method].present? && %w[moncash stripe].include?(params[:method])
      @payments = @payments.is_a?(Array) ? @payments : @payments.where(payment_method: params[:method])
      @active_method = params[:method]
    end

    # Stats
    @stats = {
      balance: @partner.credit_balance,
      spent_this_month: @partner.credits_used_this_month,
      added_this_month: @partner.credits_added_this_month,
      total_payments: @partner.partner_payments.count,
      successful_payments: @partner.partner_payments.where(status: "completed").count,
      failed_payments: @partner.partner_payments.where(status: "failed").count
    }
  end

  # GET /partner_portal/billing/history
  def history
    @partner = @current_partner
    @payments = @partner&.partner_payments&.recent || []
  end
end
