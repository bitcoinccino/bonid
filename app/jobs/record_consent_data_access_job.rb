# frozen_string_literal: true

# Async audit logging for Double-Lock consent data access.
# Runs in background so the API response is instant — audit
# writing happens a fraction of a second later without blocking.
class RecordConsentDataAccessJob < ApplicationJob
  queue_as :low
  retry_on ActiveRecord::ConnectionNotEstablished, wait: 5.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(consent_id:, ip:, scopes_used:)
    consent = TransactionConsent.find(consent_id)
    consent.record_data_access!(ip: ip, scopes_used: scopes_used)

    # Burn-after-read: invalidate Redis cache after first access
    if consent.burn_after_read?
      consent.invalidate_cache!
    end
  end
end
