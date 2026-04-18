# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# Provider-agnostic SMS sender.
#
# The gateway routes outbound SMS through one of four modes, chosen by
# `Rails.application.credentials.dig(:sms, :provider)` (or `ENV["SMS_PROVIDER"]`):
#
#   • "twilio"  — HTTPS POST to api.twilio.com Messages endpoint
#   • "digicel" — HTTPS POST to the Digicel Haiti HTTP SMS gateway
#   • "logger"  — default for dev / test: writes to Rails.logger (no outbound)
#   • "auto"    — country-code routing: +509 → Digicel, else → Twilio.
#                 Falls back to the other provider if the preferred one is
#                 not configured, and to LoggerAdapter if neither is.
#
# Callers use the single entrypoint:
#
#   SmsGateway.send!(to: "+50932001234", body: "...", context: "voter_receipt")
#
# The `context` tag is logged but not transmitted — it exists so operators
# can grep the log for a particular message flow (voter_receipt, accreditation,
# consent_otp, emergency_contact, etc.).
#
# Phone numbers are normalized to E.164 (Haiti default +509). Adapters raise
# Error on provider failure; callers inside ActiveJob rely on the retry
# behavior of the surrounding job.
class SmsGateway
  class Error                 < StandardError; end
  class ConfigurationError    < Error; end
  class DeliveryError         < Error; end
  class UnsupportedProvider   < Error; end

  HAITI_COUNTRY_CODE = "+509"

  def self.send!(to:, body:, context: nil)
    new.send!(to: to, body: body, context: context)
  end

  # Class-level normalization is exposed so other code (rate limiters, audit
  # logs) can align on the same canonical form without re-implementing.
  def self.normalize_phone(raw)
    return nil if raw.blank?

    digits = raw.to_s.gsub(/[^\d+]/, "")
    return digits if digits.start_with?("+")
    return "+#{digits}" if digits.start_with?("509") && digits.length == 11
    return "#{HAITI_COUNTRY_CODE}#{digits}" if digits.length == 8 # 8-digit Haitian local

    "+#{digits}"
  end

  def send!(to:, body:, context: nil)
    phone = self.class.normalize_phone(to)
    raise DeliveryError, "invalid phone: #{to.inspect}" if phone.blank?

    trimmed = body.to_s.strip
    raise DeliveryError, "empty SMS body" if trimmed.empty?

    adapter = resolve_adapter(phone: phone)
    result  = adapter.deliver(to: phone, body: trimmed)

    Rails.logger.info(
      "[SmsGateway] provider=#{adapter.provider_name} to=#{mask_phone(phone)} " \
      "ctx=#{context || '-'} chars=#{trimmed.length} id=#{result[:message_id] || '-'}"
    )
    result
  end

  private

  def resolve_adapter(phone:)
    provider = Rails.application.credentials.dig(:sms, :provider).presence ||
               ENV["SMS_PROVIDER"].presence ||
               "logger"

    case provider.to_s.downcase
    when "twilio"  then TwilioAdapter.new
    when "digicel" then DigicelAdapter.new
    when "logger", "stub" then LoggerAdapter.new
    when "auto"    then route_by_country(phone)
    else raise UnsupportedProvider, "unknown SMS_PROVIDER=#{provider.inspect}"
    end
  end

  # "auto" mode: pick the cheapest/most reliable provider for the destination.
  #   +509 → Digicel (native Haiti network), everything else → Twilio (global).
  # If the preferred adapter isn't configured, fall through to the other;
  # if neither is, fall through to the logger so registration never fails
  # just because SMS is down.
  def route_by_country(phone)
    prefer_digicel = phone.to_s.start_with?(HAITI_COUNTRY_CODE)
    primary        = prefer_digicel ? DigicelAdapter.new : TwilioAdapter.new
    secondary      = prefer_digicel ? TwilioAdapter.new  : DigicelAdapter.new

    return primary   if primary.configured?
    return secondary if secondary.configured?

    LoggerAdapter.new
  end

  def mask_phone(phone)
    return "-" if phone.blank?

    s = phone.to_s
    return s if s.length <= 6

    "#{s[0, 4]}••••#{s[-2, 2]}"
  end

  # ── Adapters ──────────────────────────────────────────────────────

  class LoggerAdapter
    def provider_name = "logger"

    def deliver(to:, body:)
      Rails.logger.info("[SmsGateway::Logger] → #{to}: #{body}")
      { message_id: "log-#{SecureRandom.hex(4)}", status: "logged" }
    end
  end

  class TwilioAdapter
    API_HOST = "api.twilio.com"

    def provider_name = "twilio"

    def configured?
      creds(:sid).present? && creds(:auth_token).present? && creds(:from).present?
    end

    def deliver(to:, body:)
      sid   = creds(:sid)
      token = creds(:auth_token)
      from  = creds(:from)
      raise ConfigurationError, "twilio credentials missing" if sid.blank? || token.blank? || from.blank?

      uri = URI::HTTPS.build(host: API_HOST, path: "/2010-04-01/Accounts/#{sid}/Messages.json")
      http = Net::HTTP.new(uri.host, uri.port).tap { |h| h.use_ssl = true; h.open_timeout = 5; h.read_timeout = 10 }
      req  = Net::HTTP::Post.new(uri)
      req.basic_auth(sid, token)
      req.set_form_data("To" => to, "From" => from, "Body" => body)

      res = http.request(req)
      unless res.code.to_i.between?(200, 299)
        raise DeliveryError, "twilio status=#{res.code} body=#{res.body&.slice(0, 200)}"
      end

      parsed = JSON.parse(res.body) rescue {}
      { message_id: parsed["sid"], status: parsed["status"] || "sent" }
    end

    private

    def creds(key)
      Rails.application.credentials.dig(:sms, :twilio, key).presence ||
        ENV["TWILIO_#{key.to_s.upcase}"]
    end
  end

  # Digicel Haiti offers an HTTP SMS gateway (exact endpoint varies per
  # contract). We submit as form-encoded POST; the response body carries
  # a `message_id`. Drop-in alternative adapters (e.g. Natcom) follow the
  # same shape.
  class DigicelAdapter
    def provider_name = "digicel"

    def configured?
      creds(:endpoint).present? && creds(:api_key).present?
    end

    def deliver(to:, body:)
      endpoint = creds(:endpoint)
      api_key  = creds(:api_key)
      sender   = creds(:sender_id)
      raise ConfigurationError, "digicel credentials missing" if endpoint.blank? || api_key.blank?

      uri  = URI.parse(endpoint)
      http = Net::HTTP.new(uri.host, uri.port).tap do |h|
        h.use_ssl = (uri.scheme == "https")
        h.open_timeout = 5
        h.read_timeout = 10
      end

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req.set_form_data(
        "to" => to, "from" => (sender.presence || "BonID"), "message" => body
      )

      res = http.request(req)
      unless res.code.to_i.between?(200, 299)
        raise DeliveryError, "digicel status=#{res.code} body=#{res.body&.slice(0, 200)}"
      end

      parsed = JSON.parse(res.body) rescue {}
      { message_id: parsed["message_id"] || parsed["id"], status: parsed["status"] || "sent" }
    end

    private

    def creds(key)
      Rails.application.credentials.dig(:sms, :digicel, key).presence ||
        ENV["DIGICEL_#{key.to_s.upcase}"]
    end
  end
end
