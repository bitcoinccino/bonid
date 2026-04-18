# frozen_string_literal: true

# General-purpose SMS dispatcher. All outbound SMS in the system should
# enqueue through this job so retries, logging, and provider failover
# are consistent across voter receipts, accreditation notices, consent
# OTPs, and emergency alerts.
#
# Usage:
#   SendSmsJob.perform_later("+50932001234", "Your BVT-2026-XXXX-XXXX receipt.",
#                            context: "voter_receipt")
class SendSmsJob < ApplicationJob
  queue_as :default

  # DeliveryError retries are bounded — SMS receipts are time-sensitive
  # and a permanent provider failure shouldn't hog the queue. Provider
  # ConfigurationError is NOT retried (the operator needs to fix creds).
  retry_on SmsGateway::DeliveryError, wait: :polynomially_longer, attempts: 4
  discard_on SmsGateway::ConfigurationError
  discard_on SmsGateway::UnsupportedProvider

  def perform(phone, body, context: nil)
    return if phone.blank? || body.blank?

    SmsGateway.send!(to: phone, body: body, context: context)
  end
end
