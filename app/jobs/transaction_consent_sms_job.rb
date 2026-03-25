# frozen_string_literal: true

# Stubbed SMS notification for transaction consent.
# Ready for Twilio or Digicel API integration.
class TransactionConsentSmsJob < ApplicationJob
  queue_as :default

  def perform(consent_id, otp)
    consent = TransactionConsent.find_by(id: consent_id)
    return unless consent&.pending?

    citizen = consent.citizen
    return unless citizen.phone.present?

    partner_name = consent.partner.name
    type_label = consent.transaction_type.titleize.gsub("_", " ")
    ttl_min = ((consent.expires_at - Time.current) / 60).ceil

    message = "BonID: #{partner_name} requests approval for #{type_label}. " \
              "Code: #{otp}. Expires in #{ttl_min}min."

    # === STUB: Replace with real SMS gateway ===
    # Example Twilio integration:
    # client = Twilio::REST::Client.new(ENV["TWILIO_SID"], ENV["TWILIO_AUTH_TOKEN"])
    # client.messages.create(
    #   from: ENV["TWILIO_PHONE"],
    #   to: citizen.phone,
    #   body: message
    # )

    Rails.logger.info("[TransactionConsentSmsJob] SMS stub for #{citizen.phone}: #{message}")

    consent.update_columns(sms_sent_at: Time.current)
  end
end
