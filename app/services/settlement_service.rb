# frozen_string_literal: true

# SettlementService — Records what BonID owes partners after each payment
# ========================================================================
# Called automatically when a DgiPayment completes.
# Creates a Settlement ledger entry splitting the payment into:
#   - partner_amount: the partner's official fee (e.g. DGI's 1,000 HTG for NIF)
#   - bonid_fee: BonID's service fee (e.g. 150 HTG for NIF)
#
# This is a LEDGER — it records debts, not transfers.
# Actual settlement (bank wire, Zellus transfer) happens separately.
# ========================================================================

class SettlementService
  class << self
    # Record a completed payment in the settlement ledger
    #
    # @param payment [DgiPayment] the completed payment
    # @return [Settlement, nil] the created settlement entry, or nil if no partner
    def record_payment(payment)
      return nil unless payment.completed?

      partner = find_partner_for(payment)
      return nil unless partner

      bonid_fee = DgiPayment.bongouv_fee_for(payment.form_type)
      partner_amount = payment.total_htg - bonid_fee

      # If partner amount is negative (shouldn't happen), set to 0
      partner_amount = 0 if partner_amount.negative?

      Settlement.create!(
        partner: partner,
        dgi_payment: payment,
        payment_order_id: payment.order_id,
        total_collected: payment.total_htg,
        partner_amount: partner_amount,
        bonid_fee: bonid_fee,
        currency: payment.currency,
        form_type: payment.form_type,
        description: build_description(payment),
        status: "pending",
        period_start: Time.current.beginning_of_week.to_date,
        period_end: Time.current.end_of_week.to_date,
        batch_id: Settlement.current_batch_id(partner)
      )
    rescue => e
      Rails.logger.error "[SettlementService] Failed to record settlement for payment #{payment.id}: #{e.message}"
      nil
    end

    # Settle an entire batch — mark all entries as settled
    #
    # @param batch_id [String] the batch ID
    # @param method [String] settlement method (bank_wire, zellus_transfer, etc.)
    # @param reference [String] transaction reference
    # @param admin_id [Integer] admin who approved the settlement
    def settle_batch!(batch_id:, method:, reference:, admin_id: nil, notes: nil)
      entries = Settlement.pending.where(batch_id: batch_id)
      count = entries.count
      total = entries.sum(:partner_amount)

      entries.update_all(
        status: "settled",
        settlement_method: method,
        settlement_reference: reference,
        settled_at: Time.current,
        settled_by_admin_id: admin_id,
        notes: notes,
        updated_at: Time.current
      )

      Rails.logger.info "[SettlementService] Settled batch #{batch_id}: #{count} entries, #{total} HTG via #{method}"

      { count: count, total: total, batch_id: batch_id }
    end

    # Generate a summary report for a partner
    #
    # @param partner [Partner] the partner
    # @param start_date [Date] period start
    # @param end_date [Date] period end
    # @return [Hash] summary with breakdowns by form type
    def partner_report(partner, start_date: Time.current.beginning_of_week, end_date: Time.current.end_of_week)
      entries = Settlement.for_partner(partner)
                          .where(created_at: start_date..end_date)

      by_form = entries.group(:form_type).pluck(
        :form_type,
        Arel.sql("COUNT(*)"),
        Arel.sql("SUM(partner_amount)"),
        Arel.sql("SUM(bonid_fee)"),
        Arel.sql("SUM(total_collected)")
      ).map do |form_type, count, partner_total, fee_total, collected_total|
        {
          form_type: form_type,
          count: count,
          partner_total: partner_total,
          bonid_fee_total: fee_total,
          collected_total: collected_total
        }
      end

      {
        partner: partner.name,
        period: "#{start_date.strftime('%d/%m/%Y')} — #{end_date.strftime('%d/%m/%Y')}",
        entries: entries.count,
        total_collected: entries.sum(:total_collected),
        partner_owed: entries.pending.sum(:partner_amount),
        partner_settled: entries.settled.sum(:partner_amount),
        bonid_earned: entries.sum(:bonid_fee),
        by_form_type: by_form
      }
    end

    private

    # Find the partner that should receive settlement for this payment
    def find_partner_for(payment)
      slug = Settlement::FORM_PARTNER_MAP[payment.form_type]
      return nil unless slug

      Partner.find_by(slug: slug)
    end

    # Build a human-readable description for the settlement entry
    def build_description(payment)
      label = payment.form_type_label || payment.form_type
      declaration = payment.declaration_number
      declaration ? "#{label} — #{declaration}" : label
    end
  end
end
