# frozen_string_literal: true

# DgiPaymentService — Handles citizen DGI tax payments
# ======================================================
# Orchestrates payment creation, MonCash/Natcash integration,
# and status transitions for citizen-filed DGI declarations.
#
# Usage:
#   service = DgiPaymentService.new
#   result  = service.initiate_payment(user:, record:, method: "moncash")
#   # => { payment:, redirect_url: "https://moncash.ht/..." }
#
#   result  = service.verify_moncash_payment(order_id: "DGI-ABC123-20260325")
#   # => { success: true, payment: }
#
#   service.confirm_cash_payment(payment:, confirmed_by:)
#   # => moves record from pending_cash → pending (review)
# ======================================================

class DgiPaymentService
  class PaymentError < StandardError; end

  def initialize
    @moncash = MoncashPaymentService.new
  end

  # ============================================================
  # INITIATE PAYMENT
  # Creates a DgiPayment record and routes to the right provider.
  # ============================================================
  def initiate_payment(user:, verification_record:, method:, amount_htg: 0)
    form_type = verification_record.record_type
    fee       = DgiPayment.service_fee_for(form_type)

    # For tax forms, amount_htg is the tax due. For registration forms, it's 0.
    tax_amount = DgiPayment.requires_tax_payment?(form_type) ? amount_htg.to_f : 0.0

    payment = DgiPayment.create!(
      user: user,
      verification_record: verification_record,
      form_type: form_type,
      declaration_number: verification_record.data["declaration_number"],
      payment_method: method,
      amount_htg: tax_amount,
      fee_htg: fee,
      total_htg: tax_amount + fee
    )

    case method
    when "moncash"
      initiate_moncash(payment)
    when "natcash"
      initiate_natcash(payment)
    when "zellus"
      initiate_zellus(payment)
    when "bank_transfer"
      initiate_bank_transfer(payment)
    when "cash_window"
      initiate_cash_window(payment)
    else
      raise PaymentError, "Metòd peman pa sipòte: #{method}"
    end
  end

  # ============================================================
  # PROCESS PAYMENT (for existing DgiPayment record)
  # Routes an existing payment to the right provider.
  # Used by the pay action when the citizen picks a method.
  # ============================================================
  def process_payment(payment:, method:)
    case method
    when "moncash"
      initiate_moncash(payment)
    when "natcash"
      initiate_natcash(payment)
    when "zellus"
      initiate_zellus(payment)
    when "bank_transfer"
      initiate_bank_transfer(payment)
    when "cash_window"
      initiate_cash_window(payment)
    else
      raise PaymentError, "Metòd peman pa sipòte: #{method}"
    end
  end

  # ============================================================
  # VERIFY MONCASH PAYMENT
  # Called after MonCash redirects back to our success URL.
  # ============================================================
  def verify_moncash_payment(order_id:)
    payment = DgiPayment.find_by!(order_id: order_id)
    raise PaymentError, "Peman deja konplete" if payment.completed?

    # Use existing MonCash service to verify
    token = moncash_token
    response = moncash_verify(payment.order_id, token)

    transaction = response["payment"] || response
    transaction_id = transaction["transaction_id"]&.to_s || transaction["transactionId"]&.to_s
    moncash_status = transaction["message"]&.downcase

    if moncash_status == "successful" || transaction_id.present?
      payment.complete!(transaction_id: transaction_id, provider_data: response)
      advance_record_status!(payment)
      { success: true, payment: payment }
    else
      payment.fail!(reason: "MonCash pa konfime: #{moncash_status}")
      { success: false, payment: payment, error: moncash_status }
    end
  rescue ActiveRecord::RecordNotFound
    raise PaymentError, "Peman pa jwenn pou order: #{order_id}"
  end

  # ============================================================
  # CONFIRM CASH PAYMENT (Partner action)
  # DGI agent confirms citizen paid cash at window.
  # ============================================================
  def confirm_cash_payment(payment:, confirmed_by: nil)
    raise PaymentError, "Peman deja konplete" if payment.completed?
    raise PaymentError, "Peman pa annatant kach" unless payment.status == "pending_cash"

    payment.complete!(
      transaction_id: "CASH-#{confirmed_by&.id || 'ADMIN'}-#{Time.current.to_i}",
      provider_data: { confirmed_by: confirmed_by&.id, method: "cash_window", confirmed_at: Time.current.iso8601 }
    )
    advance_record_status!(payment)
    payment
  end

  # ============================================================
  # VERIFY ZELLUS PAYMENT
  # Called after Zellus redirects back to our success URL.
  # ============================================================
  def verify_zellus_payment(checkout_token:)
    payment = DgiPayment.find_by!(payment_token: checkout_token)
    raise PaymentError, "Peman deja konplete" if payment.completed?

    # Verify checkout status via Zellus API
    response = zellus_get_checkout(checkout_token)
    status = response.dig("checkout", "status")

    if status == "completed"
      transfer_id = response.dig("checkout", "transfer_id")&.to_s
      payment.complete!(transaction_id: "ZELLUS-#{transfer_id || checkout_token}", provider_data: response)
      advance_record_status!(payment)
      { success: true, payment: payment }
    else
      payment.fail!(reason: "Zellus pa konfime: #{status}")
      { success: false, payment: payment, error: status }
    end
  rescue ActiveRecord::RecordNotFound
    raise PaymentError, "Peman pa jwenn pou checkout: #{checkout_token}"
  end

  # ============================================================
  # CONFIRM BANK TRANSFER (Partner action)
  # Partner verifies proof of bank transfer.
  # ============================================================
  def confirm_bank_transfer(payment:, reference:, confirmed_by: nil)
    raise PaymentError, "Peman deja konplete" if payment.completed?

    payment.complete!(
      transaction_id: "BANK-#{reference}",
      provider_data: { confirmed_by: confirmed_by&.id, bank_reference: reference, confirmed_at: Time.current.iso8601 }
    )
    advance_record_status!(payment)
    payment
  end

  private

  # ============================================================
  # MonCash Integration
  # ============================================================
  def initiate_moncash(payment)
    payment.mark_processing!

    token = moncash_token
    config = MONCASH_CONFIG

    response = moncash_create_payment(payment.order_id, payment.total_htg, token)
    payment_token = response.dig("payment_token", "token") || response["token"]

    raise PaymentError, "MonCash pa retounen yon token" if payment_token.blank?

    payment.update!(payment_token: payment_token)
    redirect_url = "#{config[:gateway_base]}/Moncash-pay/Redirect?token=#{payment_token}"

    { payment: payment, redirect_url: redirect_url }
  rescue => e
    payment.fail!(reason: e.message)
    raise PaymentError, "MonCash echwe: #{e.message}"
  end

  # ============================================================
  # Zellus Integration (via Zellus Checkout API)
  # ============================================================
  def initiate_zellus(payment)
    payment.mark_processing!

    callback_base = ENV.fetch("NGROK_HOST", "http://localhost:3000")
    success_url   = "#{callback_base}/citizens/dgi_payments/zellus_callback?order_id=#{payment.order_id}"
    cancel_url    = "#{callback_base}/citizens/dgi_payments/#{payment.order_id}"

    response = zellus_create_checkout(
      amount:      payment.total_htg,
      description: "#{payment.form_type_label} — #{payment.declaration_number}",
      success_url: success_url,
      cancel_url:  cancel_url,
      metadata:    { order_id: payment.order_id, form_type: payment.form_type }
    )

    checkout_token = response.dig("checkout", "token")
    checkout_url   = response.dig("checkout", "checkout_url")

    raise PaymentError, "Zellus pa retounen yon token" if checkout_token.blank?

    payment.update!(payment_token: checkout_token)
    { payment: payment, redirect_url: checkout_url }
  rescue => e
    payment.fail!(reason: e.message) unless payment.failed?
    raise PaymentError, "Zellus echwe: #{e.message}"
  end

  # ============================================================
  # Natcash Integration (placeholder — same REST pattern)
  # ============================================================
  def initiate_natcash(payment)
    # Natcash API not yet integrated — mark as pending for manual verification
    payment.update!(status: "pending")
    { payment: payment, redirect_url: nil, message: "Natcash ap disponib byento. Tanpri itilize MonCash oswa peye nan biwo." }
  end

  # ============================================================
  # Bank Transfer
  # ============================================================
  def initiate_bank_transfer(payment)
    # Generate reference for citizen to use at their bank
    payment.update!(status: "pending", provider_response: {
      bank_instructions: {
        bank: "BNC / Unibank / Sogebank / BUH",
        account: "DGI-BONID-HTG",
        reference: payment.order_id,
        amount: payment.total_htg,
        instructions: "Tanpri mete nimewo referans #{payment.order_id} nan deskripsyon transfè a."
      }
    })
    { payment: payment, redirect_url: nil }
  end

  # ============================================================
  # Cash at DGI Window
  # ============================================================
  def initiate_cash_window(payment)
    payment.mark_pending_cash!
    { payment: payment, redirect_url: nil }
  end

  # ============================================================
  # After payment completes, move the VerificationRecord forward
  # ============================================================
  def advance_record_status!(payment)
    record = payment.verification_record
    return unless record

    # Citizen-filed records: awaiting_payment → pending (review)
    # The record was saved as "pending" already, but we can add metadata
    record.data["payment"] ||= {}
    record.data["payment"]["paid"]           = true
    record.data["payment"]["paid_at"]        = payment.paid_at&.iso8601
    record.data["payment"]["order_id"]       = payment.order_id
    record.data["payment"]["transaction_id"] = payment.transaction_id
    record.data["payment"]["method"]         = payment.payment_method
    record.data["payment"]["amount_htg"]     = payment.amount_htg.to_f
    record.data["payment"]["fee_htg"]        = payment.fee_htg.to_f
    record.data["payment"]["total_htg"]      = payment.total_htg.to_f
    record.save!

    Rails.logger.info("[DgiPaymentService] Payment #{payment.order_id} completed. Record #{record.id} ready for review.")
  end

  # ============================================================
  # MonCash HTTP Helpers (reuses same config as MoncashPaymentService)
  # ============================================================
  def moncash_http(uri, read_timeout: 15)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = read_timeout
    # MonCash cert has a broken CRL — disable verification for this host only.
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http
  end

  def moncash_token
    cached = Rails.cache.read("moncash:access_token")
    return cached if cached.present?

    config = MONCASH_CONFIG
    uri = URI("#{config[:api_base]}/oauth/token")
    http = moncash_http(uri)

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Basic #{Base64.strict_encode64("#{config[:client_id]}:#{config[:client_secret]}")}"
    request["Accept"] = "application/json"
    request.set_form_data(grant_type: "client_credentials", scope: "read,write")

    response = http.request(request)
    raise PaymentError, "MonCash OAuth echwe (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    token = data["access_token"]
    Rails.cache.write("moncash:access_token", token, expires_in: [(data["expires_in"] || 3600).to_i - 300, 60].max)
    token
  end

  def moncash_create_payment(order_id, amount, token)
    config = MONCASH_CONFIG
    uri = URI("#{config[:api_base]}/v1/CreatePayment")
    http = moncash_http(uri, read_timeout: 30)

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = { amount: amount.to_f, orderId: order_id }.to_json

    response = http.request(request)
    raise PaymentError, "MonCash API erè (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  # ============================================================
  # Zellus HTTP Helpers
  # ============================================================
  def zellus_create_checkout(amount:, description:, success_url:, cancel_url:, metadata: {})
    api_base = ENV.fetch("ZELLUS_API_BASE", "https://zellus.ht")
    api_key  = ENV["ZELLUS_API_KEY"] || raise(PaymentError, "ZELLUS_API_KEY pa konfigire nan .env")
    cashtag  = ENV.fetch("ZELLUS_RECEIVER_CASHTAG", "$bonid")

    uri  = URI("#{api_base}/api/v1/checkouts")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30
    # ngrok dev certs may not verify — disable for dev
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?

    request = Net::HTTP::Post.new(uri)
    request["X-Partner-Api-Key"] = api_key
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = {
      receiver_cashtag: cashtag,
      amount:           amount.to_f,
      currency:         "htg",
      description:      description,
      success_url:      success_url,
      cancel_url:       cancel_url,
      metadata:         metadata
    }.to_json

    response = http.request(request)
    raise PaymentError, "Zellus API erè (#{response.code}): #{response.body}" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def zellus_get_checkout(token)
    api_base = ENV.fetch("ZELLUS_API_BASE", "https://zellus.ht")
    api_key  = ENV["ZELLUS_API_KEY"] || raise(PaymentError, "ZELLUS_API_KEY pa konfigire nan .env")

    uri  = URI("#{api_base}/api/v1/checkouts/#{token}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 15
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if Rails.env.development?

    request = Net::HTTP::Get.new(uri)
    request["X-Partner-Api-Key"] = api_key
    request["Accept"] = "application/json"

    response = http.request(request)
    raise PaymentError, "Zellus verifikasyon echwe (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def moncash_verify(order_id, token)
    config = MONCASH_CONFIG
    uri = URI("#{config[:api_base]}/v1/RetrieveOrderPayment")
    http = moncash_http(uri, read_timeout: 30)

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request.body = { orderId: order_id }.to_json

    response = http.request(request)
    raise PaymentError, "MonCash verifikasyon echwe (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end
end
