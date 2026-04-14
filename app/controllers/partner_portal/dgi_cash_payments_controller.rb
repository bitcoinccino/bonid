# frozen_string_literal: true

# PartnerPortal::DgiCashPaymentsController — Unified Activity Feed
# ==================================================================
# Shows ALL DGI activity: payments (all methods/statuses) and
# citizen-filed declarations. Cash/bank payments still confirmable.
# ==================================================================

module PartnerPortal
  class DgiCashPaymentsController < PartnerPortal::BaseController
    before_action :set_partner

    CITIZEN_FORM_TYPES = %w[
      nif_registration business_registration
      patente_declaration tca_declaration ras_ir_declaration
      fermage
    ].freeze

    # ============================================================
    # INDEX — Unified activity feed
    # ============================================================
    def index
      @tab = params[:tab].presence || "all"

      # --- All DGI Payments ---
      @all_payments = DgiPayment.includes(:user, :verification_record).order(created_at: :desc)

      case @tab
      when "pending"
        @payments = @all_payments.where(status: %w[pending_cash pending])
                      .where(payment_method: %w[cash_window bank_transfer])
      when "completed"
        @payments = @all_payments.where(status: "completed")
      when "declarations"
        @payments = DgiPayment.none # handled separately
      else
        @payments = @all_payments
      end

      # Search
      if params[:search].present? && @tab != "declarations"
        q = "%#{params[:search]}%"
        @payments = @payments
          .joins(:user)
          .where(
            "dgi_payments.order_id ILIKE :q OR users.first_name ILIKE :q OR users.last_name ILIKE :q OR users.email ILIKE :q",
            q: q
          )
      end

      # Filter by payment method
      if params[:method].present? && @tab != "declarations"
        @payments = @payments.where(payment_method: params[:method])
      end

      @payments = @payments.page(params[:page]).per(20) unless @tab == "declarations"

      # --- Citizen Declarations (for declarations tab or all tab) ---
      @declarations = VerificationRecord
                        .where(record_type: CITIZEN_FORM_TYPES)
                        .where("data->>'filed_by' = ?", "citizen")
                        .includes(:user)
                        .order(created_at: :desc)

      if params[:search].present? && @tab == "declarations"
        q = "%#{params[:search]}%"
        @declarations = @declarations
          .joins(:user)
          .where(
            "users.first_name ILIKE :q OR users.last_name ILIKE :q OR " \
            "verification_records.data->>'declaration_number' ILIKE :q",
            q: q
          )
      end

      @declarations = @declarations.page(params[:page]).per(20) if @tab == "declarations"

      # --- Stats ---
      @stats = {
        total_payments: DgiPayment.count,
        pending_confirm: DgiPayment.where(status: %w[pending_cash pending])
                           .where(payment_method: %w[cash_window bank_transfer]).count,
        completed: DgiPayment.where(status: "completed").count,
        total_declarations: VerificationRecord.where(record_type: CITIZEN_FORM_TYPES)
                              .where("data->>'filed_by' = ?", "citizen").count,
        revenue_htg: DgiPayment.where(status: "completed").sum(:amount_htg).to_i +
                     DgiPayment.where(status: "completed").sum(:fee_htg).to_i
      }
    end

    # ============================================================
    # CONFIRM — Agent confirms citizen paid cash/bank
    # ============================================================
    def confirm
      payment = DgiPayment.find(params[:id])

      unless payment.pending?
        return redirect_to partner_portal_dgi_cash_payments_path(tab: "pending"),
                          alert: "Peman sa a deja trete."
      end

      service = DgiPaymentService.new

      if payment.payment_method == "cash_window"
        service.confirm_cash_payment(payment: payment, confirmed_by: current_portal_user)
      elsif payment.payment_method == "bank_transfer"
        reference = params[:bank_reference].to_s.strip
        if reference.blank?
          return redirect_to partner_portal_dgi_cash_payments_path(tab: "pending"),
                            alert: "Tanpri antre referans transfè bankè a."
        end
        service.confirm_bank_transfer(payment: payment, reference: reference, confirmed_by: current_portal_user)
      end

      redirect_to partner_portal_dgi_cash_payments_path(tab: "pending"),
                  notice: "Peman #{payment.order_id} konfime avèk siksè."
    rescue DgiPaymentService::PaymentError => e
      redirect_to partner_portal_dgi_cash_payments_path(tab: "pending"), alert: "Erè: #{e.message}"
    end

    # ============================================================
    # LOOKUP — Agent scans QR/enters order_id to find payment
    # ============================================================
    def lookup
      if params[:order_id].present?
        @payment = DgiPayment.find_by(order_id: params[:order_id].strip.upcase)
        flash.now[:alert] = "Peman pa jwenn pou: #{params[:order_id]}" unless @payment
      end
    end

    private

    def set_partner
      @partner = @current_partner
    end
  end
end
