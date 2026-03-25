# frozen_string_literal: true

# Sends a reminder email 2 minutes after consent creation if still pending.
class TransactionConsentReminderJob < ApplicationJob
  queue_as :default

  def perform(consent_id, otp)
    consent = TransactionConsent.find_by(id: consent_id)
    return unless consent&.pending?
    return if consent.metadata&.dig("reminder_sent")

    # Mark reminder as sent (prevent duplicates)
    consent.metadata["reminder_sent"] = true
    consent.save!(touch: false)

    Citizens::TransactionConsentMailer
      .with(consent: consent, otp: otp)
      .consent_reminder
      .deliver_later
  end
end
