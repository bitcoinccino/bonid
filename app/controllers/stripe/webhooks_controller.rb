# frozen_string_literal: true

module Stripe
  class WebhooksController < ActionController::API
    # Handles incoming Stripe webhooks for credit top-ups
    def create
      payload    = request.body.read
      sig_header = request.headers["Stripe-Signature"]

      event = Stripe::Webhook.construct_event(
        payload,
        sig_header,
        ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)
      )

      case event.type
      when "checkout.session.completed"
        handle_checkout_session(event.data.object)
      when "invoice.payment_succeeded"
        handle_invoice_payment_succeeded(event.data.object)
      else
        Rails.logger.info("[StripeWebhook] Unhandled event: #{event.type}")
      end

      render json: { status: "ok" }
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error("[StripeWebhookError] #{e.class}: #{e.message}")
      render json: { error: e.message }, status: :bad_request
    end

    private

    def handle_checkout_session(session)
      partner = Partner.find_by(stripe_session_id: session.id)
      return unless partner

      Rails.logger.info("[StripeWebhook] Checkout completed for Partner ##{partner.id}")
    end

    def handle_invoice_payment_succeeded(invoice)
      partner = Partner.find_by(stripe_customer_id: invoice.customer)
      Rails.logger.info("[StripeWebhook] Payment succeeded for Partner ##{partner&.id}")
    end
  end
end
