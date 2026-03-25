# frozen_string_literal: true

# MoncashReconciliationJob
#
# Runs every 15 minutes to auto-reconcile pending MonCash payments.
# Handles the case where MonCash callback fails due to connectivity issues
# (common in Haiti) — partner paid but credits weren't added.
#
class MoncashReconciliationJob < ApplicationJob
  queue_as :billing

  def perform
    pending_payments = PartnerPayment
      .where(payment_method: "moncash", status: "pending")
      .where("created_at > ?", 24.hours.ago)
      .where("reconciliation_attempts < ?", 5)
      .order(created_at: :asc)

    Rails.logger.info("[MonCashReconciliation] Checking #{pending_payments.count} pending payments...")

    service = MoncashPaymentService.new

    pending_payments.find_each do |payment|
      reconcile_payment(service, payment)
    end

    Rails.logger.info("[MonCashReconciliation] Completed.")
  end

  private

  def reconcile_payment(service, payment)
    result = service.verify_payment(order_id: payment.order_id)

    payment.update!(
      reconciliation_attempts: payment.reconciliation_attempts.to_i + 1,
      reconciled_at: result[:success] ? Time.current : nil,
      reconciled_by: result[:success] ? "auto" : nil
    )

    if result[:success]
      Rails.logger.info("[MonCashReconciliation] Auto-reconciled: #{payment.order_id} for #{payment.partner.slug}")
    end
  rescue MoncashPaymentService::PaymentError => e
    payment.update!(
      reconciliation_attempts: payment.reconciliation_attempts.to_i + 1,
      last_reconciliation_error: e.message
    )
    Rails.logger.warn("[MonCashReconciliation] Failed: #{payment.order_id} — #{e.message}")
  rescue => e
    Rails.logger.error("[MonCashReconciliation] Unexpected error for #{payment.order_id}: #{e.message}")
  end
end
