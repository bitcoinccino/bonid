# frozen_string_literal: true

module Admin
  class SettlementsController < Admin::BaseController
    # GET /admin/settlements
    def index
      # ── Summary Cards ──
      @total_pending    = Settlement.pending.sum(:partner_amount)
      @total_settled    = Settlement.settled.sum(:partner_amount)
      @bonid_revenue    = Settlement.sum(:bonid_fee)

      # ── Per-Partner Breakdown ──
      partner_ids = Settlement.distinct.pluck(:partner_id)
      @partners = Partner.where(id: partner_ids).order(:name)
      @partner_balances = Settlement.pending
                                    .group(:partner_id)
                                    .sum(:partner_amount)

      # ── Filtered Scope ──
      scope = Settlement.includes(:partner).recent

      scope = scope.where(partner_id: params[:partner_id]) if params[:partner_id].present?
      scope = scope.where(status: params[:status])         if params[:status].present?
      scope = scope.where("created_at >= ?", params[:from].to_date.beginning_of_day) if params[:from].present?
      scope = scope.where("created_at <= ?", params[:to].to_date.end_of_day)         if params[:to].present?

      @settlements = scope.page(params[:page]).per(50)
      @partner_options = Partner.order(:name)
    end

    # GET /admin/settlements/:id
    def show
      @settlement = Settlement.includes(:partner).find(params[:id])
    end

    # POST /admin/settlements/settle_batch
    def settle_batch
      batch_id = params[:batch_id]
      method   = params[:settlement_method]
      reference = params[:settlement_reference]
      notes    = params[:notes]

      settlements = Settlement.pending.where(batch_id: batch_id)

      if settlements.none?
        redirect_to admin_settlements_path, alert: "Okenn batch pa jwenn oswa deja regle."
        return
      end

      settled_count = 0
      settlements.find_each do |settlement|
        settlement.settle!(
          method: method,
          reference: reference,
          admin_id: current_admin_user&.id,
          notes: notes
        )
        settled_count += 1
      end

      redirect_to admin_settlements_path,
                  notice: "#{settled_count} regleman make kòm regle avèk referans: #{reference}"
    end
  end
end
