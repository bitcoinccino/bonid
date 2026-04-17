# frozen_string_literal: true

require "net/http"
require "json"
require "base64"

# MoncashPaymentService
# Wraps the MonCash REST API for partner credit top-up payments.
#
# MonCash flow:
#   1. create_payment_for_credits → POST /v1/CreatePayment → returns redirect URL
#   2. User pays on MonCash page
#   3. MonCash redirects to success/error callback URL
#   4. verify_payment → GET /v1/RetrieveOrderPayment → confirms transaction
#   5. activate_credit_top_up → adds credits to partner wallet
#
class MoncashPaymentService
  class PaymentError < StandardError; end

  def initialize
    @config = MONCASH_CONFIG
    validate_config!
  end

  # ============================================================
  # VERIFY PAYMENT
  # Called after MonCash redirects back to our success URL.
  # ============================================================
  def verify_payment(order_id:)
    payment = PartnerPayment.find_by!(order_id: order_id)
    raise PaymentError, "Payment already completed" if payment.completed?

    token = fetch_access_token
    response = moncash_post("/v1/RetrieveOrderPayment", {
      orderId: order_id
    }, token)

    # MonCash returns transaction details
    transaction = response["payment"] || response
    transaction_id = transaction["transaction_id"]&.to_s || transaction["transactionId"]&.to_s
    moncash_status = transaction["message"]&.downcase

    if moncash_status == "successful" || transaction_id.present?
      payment.complete!(transaction_id: transaction_id)
      activate_credit_top_up(payment)

      { success: true, payment: payment }
    else
      payment.fail!(reason: "MonCash payment not confirmed: #{moncash_status}")
      { success: false, payment: payment, error: moncash_status }
    end
  rescue ActiveRecord::RecordNotFound
    raise PaymentError, "Payment not found for order: #{order_id}"
  rescue => e
    Rails.logger.error("[MoncashPaymentService] verify_payment failed: #{e.message}")
    raise PaymentError, "Payment verification failed: #{e.message}"
  end

  # ============================================================
  # CREATE PAYMENT FOR CREDITS (prepaid top-up)
  # Used by CreditsController — payment record already exists.
  # ============================================================
  def create_payment_for_credits(partner:, payment:, amount_htg:)
    token = fetch_access_token
    response = moncash_post("/v1/CreatePayment", {
      amount: amount_htg,
      orderId: payment.order_id
    }, token)

    payment_token = response.dig("payment_token", "token") || response["token"]
    raise PaymentError, "MonCash did not return a payment token" if payment_token.blank?

    payment.update!(payment_token: payment_token)
    redirect_url = "#{@config[:gateway_base]}/Moncash-pay/Redirect?token=#{payment_token}"

    { payment: payment, redirect_url: redirect_url }
  rescue => e
    payment&.fail!(reason: e.message) if payment&.persisted?
    raise PaymentError, "MonCash credit top-up failed: #{e.message}"
  end

  # ============================================================
  # ACTIVATE CREDIT TOP-UP
  # Adds credits to partner's wallet after successful MonCash payment.
  # ============================================================
  def activate_credit_top_up(payment)
    partner = payment.partner
    credits = payment.credits || payment.metadata&.dig("credits").to_d

    if credits <= 0
      # Fallback: calculate credits from HTG amount (1 credit = $1.00)
      credits = CurrencyRate.htg_to_credits(payment.amount) || (BigDecimal(payment.amount.to_s) / BigDecimal("1.5")).round(2)
    end

    partner.top_up_credits!(
      amount: credits,
      payment_method: "moncash",
      transaction_id: payment.transaction_id,
      description: "+$#{'%.2f' % credits} Credits (MonCash)"
    )

    payment.update!(credits: credits)

    # Send receipt email
    Partners::BillingMailer.credit_receipt(partner, payment, credits, partner.credit_balance).deliver_later

    Rails.logger.info(
      "[MoncashPaymentService] Credits topped up: #{partner.slug} +#{credits} credits " \
      "(#{payment.formatted_amount}, order: #{payment.order_id})"
    )
  end

  private

  # ============================================================
  # FETCH ACCESS TOKEN (cached)
  # POST /oauth/token with Basic Auth
  # ============================================================
  def fetch_access_token
    cached = Rails.cache.read("moncash:access_token")
    return cached if cached.present?

    uri = URI("#{@config[:api_base]}/oauth/token")
    http = build_moncash_http(uri, read_timeout: 15)

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Basic #{Base64.strict_encode64("#{@config[:client_id]}:#{@config[:client_secret]}")}"
    request["Accept"] = "application/json"
    request.set_form_data(grant_type: "client_credentials", scope: "read,write")

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      raise PaymentError, "MonCash OAuth failed (#{response.code}): #{response.body}"
    end

    data = JSON.parse(response.body)
    token = data["access_token"]
    expires_in = (data["expires_in"] || 3600).to_i

    # Cache with 5-minute buffer
    Rails.cache.write("moncash:access_token", token, expires_in: [ expires_in - 300, 60 ].max)

    token
  end

  # ============================================================
  # HTTP Helpers
  # ============================================================
  def moncash_post(path, body, access_token)
    uri = URI("#{@config[:api_base]}#{path}")
    http = build_moncash_http(uri, read_timeout: 30)

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = body.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      error_body = begin; JSON.parse(response.body); rescue; response.body; end
      raise PaymentError, "MonCash API error (#{response.code}): #{error_body}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise PaymentError, "Invalid MonCash response: #{e.message}"
  end

  def build_moncash_http(uri, read_timeout: 15)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = read_timeout
    # MonCash cert has a broken CRL — disable verification for this host.
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http
  end

  def sandbox?
    @config[:environment] != "production"
  end

  def validate_config!
    if @config[:client_id].blank? || @config[:client_secret].blank?
      Rails.logger.warn("[MoncashPaymentService] MonCash credentials not configured. Payment features will not work.")
    end
  end
end
