# frozen_string_literal: true

class TransactionConsentCallbackRetryJob < ApplicationJob
  queue_as :webhooks

  def perform(consent_id, attempt)
    consent = TransactionConsent.find_by(id: consent_id)
    return unless consent

    BonidNotifier.notify_transaction_consent(consent, attempt: attempt)
  end
end
