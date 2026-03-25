# frozen_string_literal: true

# Runs every minute to expire stale transaction consents.
# Uses batch updates to avoid DB spikes during peak banking hours.
class ExpireTransactionConsentsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    expired_ids = TransactionConsent
      .where(status: :pending)
      .where("expires_at < ?", Time.current)
      .limit(BATCH_SIZE)
      .pluck(:id)

    return if expired_ids.empty?

    # Batch update for performance
    TransactionConsent.where(id: expired_ids).update_all(status: 3) # 3 = expired

    # Notify partners via webhook for each expired consent
    TransactionConsent.where(id: expired_ids).includes(:partner, :citizen).find_each do |consent|
      consent.append_audit!("expired", reason: "TTL exceeded")
      BonidNotifier.notify_transaction_consent(consent)
    rescue => e
      Rails.logger.warn("[ExpireTransactionConsentsJob] Webhook failed for #{consent.id}: #{e.message}")
    end

    Rails.logger.info("[ExpireTransactionConsentsJob] Expired #{expired_ids.size} consents")
  end
end
