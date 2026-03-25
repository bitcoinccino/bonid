# frozen_string_literal: true

module Moncash
  class CallbacksController < ApplicationController
    # MonCash redirects the user here after payment
    # No auth required — user comes from MonCash's payment page
    skip_before_action :verify_authenticity_token, only: [:success]

    # GET /moncash/success?orderId=BONID-XXXXXX-20260228
    def success
      order_id = params[:orderId] || params[:order_id]

      if order_id.blank?
        redirect_to partner_portal_credits_path, alert: "Peman an pa t ka verifye. Eseye ankò."
        return
      end

      service = MoncashPaymentService.new
      result = service.verify_payment(order_id: order_id)

      if result[:success]
        redirect_to partner_portal_credits_path,
                    notice: "Peman ou reyisi! Kredi ou ajoute. Mèsi!"
      else
        redirect_to partner_portal_credits_path,
                    alert: "Peman an pa t konfime pa MonCash. Kontakte sipò si lajan ou te debite."
      end
    rescue MoncashPaymentService::PaymentError => e
      Rails.logger.error("[MonCash Callback] #{e.message}")
      redirect_to partner_portal_credits_path,
                  alert: "Gen yon erè ak peman an: #{e.message}"
    end

    # GET /moncash/error
    def error
      Rails.logger.warn("[MonCash Callback] Payment error/cancelled. Params: #{params.to_unsafe_h}")
      redirect_to partner_portal_credits_path,
                  alert: "Peman MonCash la pa t mache. Ou ka eseye ankò oswa chwazi yon lòt metòd peman."
    end
  end
end
