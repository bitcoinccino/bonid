# frozen_string_literal: true

# Citizens::DgiPaymentsController — Payment flow for citizen DGI filings
# ========================================================================
# Handles payment method selection, MonCash redirect, callback verification,
# and payment status display.
# ========================================================================

module Citizens
  class DgiPaymentsController < Citizens::BaseController
    before_action :set_citizen
    before_action :find_payment, only: [ :show, :pay, :receipt ]
    before_action :set_immersive, only: [ :show, :receipt ]

    # ============================================================
    # SHOW — Payment page (pick method, see breakdown)
    # ============================================================
    def show
      @record = @payment.verification_record
      redirect_to citizens_dgi_path(@record), notice: "Peman deja konplete." if @payment.completed?
    end

    # ============================================================
    # PAY — Initiate payment with chosen method
    # ============================================================
    def pay
      method = params[:payment_method]
      unless DgiPayment::PAYMENT_METHODS.include?(method)
        return redirect_to citizens_dgi_payment_path(@payment), alert: "Metòd peman pa valid."
      end

      @payment.update!(payment_method: method, status: "pending")
      service = DgiPaymentService.new

      begin
        result = service.process_payment(payment: @payment, method: method)

        if result[:redirect_url]
          redirect_to result[:redirect_url], allow_other_host: true
        else
          redirect_to citizens_dgi_payment_path(@payment),
                      notice: payment_instructions(method)
        end
      rescue DgiPaymentService::PaymentError => e
        redirect_to citizens_dgi_payment_path(@payment), alert: "Erè peman: #{e.message}"
      end
    end

    # ============================================================
    # MONCASH CALLBACK — MonCash redirects here after payment
    # ============================================================
    def moncash_callback
      order_id = params[:orderId] || params[:order_id]
      unless order_id.present?
        return redirect_to citizens_dgi_index_path, alert: "Peman pa valid."
      end

      service = DgiPaymentService.new
      result = service.verify_moncash_payment(order_id: order_id)

      if result[:success]
        redirect_to citizens_dgi_payment_receipt_path(result[:payment]),
                    notice: "Peman konplete avèk siksè!"
      else
        redirect_to citizens_dgi_payment_path(result[:payment]),
                    alert: "Peman pa konfime. Tanpri eseye ankò."
      end
    rescue DgiPaymentService::PaymentError => e
      redirect_to citizens_dgi_index_path, alert: "Erè verifikasyon peman: #{e.message}"
    end

    # ============================================================
    # ZELLUS CALLBACK — Zellus redirects here after checkout
    # ============================================================
    def zellus_callback
      checkout_token = params[:checkout_token]
      order_id       = params[:order_id]

      unless checkout_token.present? && order_id.present?
        return redirect_to citizens_dgi_index_path, alert: "Peman pa valid."
      end

      service = DgiPaymentService.new
      result = service.verify_zellus_payment(checkout_token: checkout_token)

      if result[:success]
        redirect_to receipt_citizens_dgi_payment_path(result[:payment]),
                    notice: "Peman Zellus konplete avèk siksè!"
      else
        redirect_to citizens_dgi_payment_path(result[:payment]),
                    alert: "Peman Zellus pa konfime. Tanpri eseye ankò."
      end
    rescue DgiPaymentService::PaymentError => e
      redirect_to citizens_dgi_index_path, alert: "Erè verifikasyon peman Zellus: #{e.message}"
    end

    # ============================================================
    # RECEIPT — Digital receipt after successful payment
    # ============================================================
    def receipt
      unless @payment.completed?
        return redirect_to citizens_dgi_payment_path(@payment), alert: "Peman poko konplete."
      end
      @record = @payment.verification_record
      # Load reviewing agent (if record was reviewed by a partner agent)
      if @record&.data&.dig("reviewed_by").present?
        @agent = User.find_by(email: @record.data["reviewed_by"])
      end
      # Load the partner that processed it
      @partner = @record&.partner
    end

    # ============================================================
    # INDEX — Payment history
    # ============================================================
    def index
      @payments = DgiPayment.for_user(@citizen).recent.page(params[:page]).per(15)
    end

    private

    def set_citizen
      @citizen = current_citizen
    end

    def find_payment
      @payment = DgiPayment.for_user(@citizen).find_by!(order_id: params[:order_id])
    rescue ActiveRecord::RecordNotFound
      redirect_to citizens_dgi_index_path, alert: "Peman pa jwenn."
    end

    def set_immersive
      @immersive_form = true
    end

    def payment_instructions(method)
      case method
      when "bank_transfer"
        "Tanpri fè transfè bankè ak referans: #{@payment.order_id}. Peman w ap verifye nan 24-48è."
      when "cash_window"
        "Prezante nimewo #{@payment.order_id} nan biwo DGI pou peye kach. Peman w ap konfime pa ajan DGI a."
      when "natcash"
        "Natcash ap disponib byento. Tanpri itilize MonCash oswa peye nan biwo."
      else
        "Ap trete peman..."
      end
    end
  end
end
