# frozen_string_literal: true

# Settlement — Tracks what BonID owes each partner after collecting payments
# ==========================================================================
# Every time a citizen pays (Zellus, MonCash, bank, cash), a Settlement entry
# records how much goes to the partner vs. how much BonID keeps as service fee.
#
# Settlements are grouped into weekly batches for reconciliation.
# Admin marks batches as "settled" when they wire/transfer the funds.
#
# Status lifecycle:
#   pending  → settled   (admin confirms transfer)
#   pending  → disputed  (discrepancy found)
#   disputed → settled   (resolved)
# ==========================================================================

class Settlement < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================
  belongs_to :partner
  belongs_to :dgi_payment, optional: true

  # ============================================================
  # Constants
  # ============================================================
  STATUSES = %w[pending settled disputed].freeze
  SETTLEMENT_METHODS = %w[bank_wire zellus_transfer check cash manual].freeze

  # Map form types to their partner slug
  # This lets us auto-assign the right partner for each payment
  FORM_PARTNER_MAP = {
    "nif_registration"      => "direction-generale-des-impots-dgi",
    "business_registration" => "direction-generale-des-impots-dgi",
    "patente_declaration"   => "direction-generale-des-impots-dgi",
    "tca_declaration"       => "direction-generale-des-impots-dgi",
    "ras_ir_declaration"    => "direction-generale-des-impots-dgi",
    "fermage"               => "direction-generale-des-impots-dgi",
    "election_registration" => "conseil-electoral-provisoire"
  }.freeze

  # ============================================================
  # Validations
  # ============================================================
  validates :status,          inclusion: { in: STATUSES }
  validates :total_collected,  presence: true, numericality: { greater_than: 0 }
  validates :partner_amount,   presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :bonid_fee,        presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :settlement_method, inclusion: { in: SETTLEMENT_METHODS }, allow_nil: true

  # ============================================================
  # Scopes
  # ============================================================
  scope :pending,    -> { where(status: "pending") }
  scope :settled,    -> { where(status: "settled") }
  scope :disputed,   -> { where(status: "disputed") }
  scope :unsettled,  -> { where(status: %w[pending disputed]) }
  scope :for_partner, ->(partner) { where(partner: partner) }
  scope :for_period, ->(start_date, end_date) { where(period_start: start_date, period_end: end_date) }
  scope :this_week,  -> { where("created_at >= ?", Time.current.beginning_of_week) }
  scope :this_month, -> { where("created_at >= ?", Time.current.beginning_of_month) }
  scope :recent,     -> { order(created_at: :desc) }

  # ============================================================
  # Status Methods
  # ============================================================
  def pending?   = status == "pending"
  def settled?   = status == "settled"
  def disputed?  = status == "disputed"

  def settle!(method:, reference:, admin_id: nil, notes: nil)
    update!(
      status: "settled",
      settlement_method: method,
      settlement_reference: reference,
      settled_at: Time.current,
      settled_by_admin_id: admin_id,
      notes: notes
    )
  end

  def dispute!(notes:, admin_id: nil)
    update!(
      status: "disputed",
      notes: notes,
      settled_by_admin_id: admin_id
    )
  end

  # ============================================================
  # Display Helpers
  # ============================================================
  def formatted_partner_amount
    number_to_currency_htg(partner_amount)
  end

  def formatted_bonid_fee
    number_to_currency_htg(bonid_fee)
  end

  def formatted_total
    number_to_currency_htg(total_collected)
  end

  def status_label
    case status
    when "pending"  then "Annatant"
    when "settled"  then "Regle"
    when "disputed" then "Konteste"
    end
  end

  def status_badge_class
    case status
    when "pending"  then "bg-warning text-dark"
    when "settled"  then "bg-success"
    when "disputed" then "bg-danger"
    end
  end

  # ============================================================
  # Class Methods — Aggregation
  # ============================================================

  # Running balance owed to a specific partner
  def self.balance_owed_to(partner)
    pending.for_partner(partner).sum(:partner_amount)
  end

  # Total BonID has earned in service fees
  def self.total_bonid_revenue(since: nil)
    scope = settled
    scope = scope.where("settled_at >= ?", since) if since
    scope.sum(:bonid_fee)
  end

  # Summary per partner for a date range
  def self.partner_summary(partner, start_date: nil, end_date: nil)
    scope = for_partner(partner)
    scope = scope.where("created_at >= ?", start_date) if start_date
    scope = scope.where("created_at <= ?", end_date) if end_date

    {
      total_transactions: scope.count,
      total_collected: scope.sum(:total_collected),
      partner_owed: scope.pending.sum(:partner_amount),
      partner_settled: scope.settled.sum(:partner_amount),
      bonid_earned: scope.sum(:bonid_fee),
      disputed_count: scope.disputed.count
    }
  end

  # Generate a batch ID for the current week
  def self.current_batch_id(partner)
    week = Time.current.strftime("%Y-W%V")
    "BATCH-#{week}-#{partner.slug&.upcase || partner.id}"
  end

  private

  def number_to_currency_htg(amount)
    "#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} HTG"
  end
end
