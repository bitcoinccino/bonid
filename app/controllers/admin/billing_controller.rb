# frozen_string_literal: true

module Admin
  class BillingController < Admin::BaseController
    # GET /admin/billing
    def index
      # ── Revenue Summary ──
      @total_revenue = PartnerPayment.successful.sum(:amount)
      @revenue_this_month = PartnerPayment.successful
                                          .where("paid_at >= ?", Time.current.beginning_of_month)
                                          .sum(:amount)
      @total_active_credits = Partner.where(active: true).sum(:credit_balance)
      @total_partners = Partner.where.not(verified_at: nil).count

      # ── Revenue by Day (last 30 days) ──
      @revenue_by_day = PartnerPayment.successful
                                      .where("paid_at >= ?", 30.days.ago)
                                      .group("DATE(paid_at)")
                                      .order("DATE(paid_at)")
                                      .sum(:amount)

      # ── Credit Usage by Day (last 30 days) ──
      @usage_by_day = CreditLedgerEntry.deductions
                                       .where("created_at >= ?", 30.days.ago)
                                       .group("DATE(created_at)")
                                       .order("DATE(created_at)")
                                       .sum("ABS(amount)")

      # ── Top Partners by Spending ──
      @top_spenders = CreditLedgerEntry.deductions
                                       .where("created_at >= ?", 30.days.ago)
                                       .group(:partner_id)
                                       .order(Arel.sql("SUM(ABS(amount)) DESC"))
                                       .limit(10)
                                       .sum("ABS(amount)")
      @top_spender_partners = Partner.where(id: @top_spenders.keys).index_by(&:id)

      # ── Recent Payments ──
      @recent_payments = PartnerPayment.includes(:partner).recent.limit(10)

      # ── Low Balance Partners ──
      @low_balance_partners = Partner.where(active: true)
                                     .where("credit_balance < ?", 5)
                                     .order(:credit_balance)
                                     .limit(10)
    end

    # GET /admin/billing/credit_ledger
    def credit_ledger
      scope = CreditLedgerEntry.includes(:partner).recent

      scope = scope.where(partner_id: params[:partner_id]) if params[:partner_id].present?
      scope = scope.where(entry_type: params[:entry_type]) if params[:entry_type].present?
      scope = scope.where("created_at >= ?", params[:from].to_date.beginning_of_day) if params[:from].present?
      scope = scope.where("created_at <= ?", params[:to].to_date.end_of_day) if params[:to].present?

      @entries = scope.page(params[:page]).per(50)
      @partner_options = Partner.order(:name)

      respond_to do |format|
        format.html
        format.csv { send_data export_ledger_csv(scope), filename: "credit_ledger_#{Time.current.strftime('%Y%m%d_%H%M')}.csv" }
      end
    end

    # GET /admin/billing/payments
    def payments
      scope = PartnerPayment.includes(:partner).recent

      scope = scope.where(partner_id: params[:partner_id]) if params[:partner_id].present?
      scope = scope.where(payment_method: params[:payment_method]) if params[:payment_method].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where("created_at >= ?", params[:from].to_date.beginning_of_day) if params[:from].present?
      scope = scope.where("created_at <= ?", params[:to].to_date.end_of_day) if params[:to].present?

      @payments = scope.page(params[:page]).per(50)
      @partner_options = Partner.order(:name)

      # ── Summary Metrics ──
      @metrics = {
        total: scope.count,
        completed: scope.successful.count,
        pending: scope.pending.count,
        failed: scope.failed.count,
        total_amount: scope.successful.sum(:amount),
        moncash_amount: scope.successful.moncash.sum(:amount),
        stripe_amount: scope.successful.stripe.sum(:amount)
      }

      respond_to do |format|
        format.html
        format.csv { send_data export_payments_csv(scope), filename: "payments_#{Time.current.strftime('%Y%m%d_%H%M')}.csv" }
      end
    end

    private

    def export_ledger_csv(scope)
      CSV.generate(headers: true) do |csv|
        csv << %w[Timestamp Partner Type Amount Balance_After Endpoint Description]
        scope.find_each do |entry|
          csv << [
            entry.created_at.strftime("%Y-%m-%d %H:%M:%S"),
            entry.partner&.name,
            entry.entry_type,
            entry.formatted_amount,
            entry.balance_after,
            entry.endpoint_key,
            entry.description
          ]
        end
      end
    end

    def export_payments_csv(scope)
      CSV.generate(headers: true) do |csv|
        csv << %w[Timestamp Partner Order_ID Method Amount Currency Status Transaction_ID Paid_At]
        scope.find_each do |payment|
          csv << [
            payment.created_at.strftime("%Y-%m-%d %H:%M:%S"),
            payment.partner&.name,
            payment.order_id,
            payment.payment_method,
            payment.amount,
            payment.currency,
            payment.status,
            payment.transaction_id,
            payment.paid_at&.strftime("%Y-%m-%d %H:%M:%S")
          ]
        end
      end
    end
  end
end
