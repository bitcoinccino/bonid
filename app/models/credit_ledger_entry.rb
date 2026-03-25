# frozen_string_literal: true

# CreditLedgerEntry
#
# Immutable ledger of all credit transactions for a partner.
# Every top-up and every API deduction gets a row here.
#
# 1 Credit = $1.00 USD
# Stored as decimal(10,2) — use BigDecimal for all arithmetic.
#
class CreditLedgerEntry < ApplicationRecord
  belongs_to :partner

  # Entry types
  ENTRY_TYPES = %w[top_up deduction bonus refund adjustment free_lookup].freeze

  validates :amount, presence: true, numericality: true
  validates :amount, numericality: { other_than: 0 }, unless: -> { entry_type == "free_lookup" }
  validates :balance_after, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :entry_type, presence: true, inclusion: { in: ENTRY_TYPES }

  # ============================================================
  # SCOPES
  # ============================================================
  scope :recent,         -> { order(created_at: :desc) }
  scope :top_ups,        -> { where(entry_type: "top_up") }
  scope :deductions,     -> { where(entry_type: "deduction") }
  scope :free_lookups,   -> { where(entry_type: "free_lookup") }
  scope :refunds,        -> { where(entry_type: "refund") }
  scope :portal_lookups, -> { where(endpoint_key: PORTAL_LOOKUP_ENDPOINT) }
  scope :this_month,     -> { where("created_at >= ?", Time.current.beginning_of_month) }
  scope :today,          -> { where("created_at >= ?", Time.current.beginning_of_day) }

  # ============================================================
  # CREDIT COST MAP
  # Five tiers — sector-specific, Haitian-market friendly
  #
  #   Standard:           $0.49 — basic lookups
  #   Health & Biometric:  $0.99 — blood type, allergies, conditions, physical profile
  #   Civil & Social:      $1.29 — family, emergency contacts, social handles
  #   Verification:        $1.49 — identity data, consent (no liveness)
  #   Premium:             $1.99 — liveness + face match, crime, crypto
  #
  # Premium is priced to absorb 2–3 failed liveness attempts per successful
  # conversion (billed on success only) plus S3 audit image storage.
  # ============================================================
  # ── Portal Free Daily Allowance ──
  # Partners get 10 free manual lookups per day in the portal UI.
  # After that, each lookup costs $0.49 (Standard tier).
  FREE_DAILY_PORTAL_LOOKUPS = 10
  PORTAL_LOOKUP_ENDPOINT = "PartnerPortal::BonidLookupsController#create"

  CREDIT_COSTS = {
    # ── Standard ($0.49) ──
    "Api::V1::QrScanController#verify"            => BigDecimal("0.49"),
    "Api::V1::IdentityController#status"           => BigDecimal("0.49"),
    "PartnerPortal::BonidLookupsController#create" => BigDecimal("0.49"),
    "Api::V1::PublicController#bonid_lookup"        => BigDecimal("0"),
    "Api::V1::CertificatesController#verify"        => BigDecimal("0"),
    "Api::V1::CertificatesController#public_key"    => BigDecimal("0"),

    # ── Health & Biometric ($0.99) ──
    "Api::V1::IdentityController#show:health"       => BigDecimal("0.99"),
    "Api::V1::IdentityController#show:physical"     => BigDecimal("0.99"),

    # ── Civil & Social ($1.29) ──
    "Api::V1::IdentityController#show:civil"        => BigDecimal("1.29"),
    "Api::V1::IdentityController#show:social"       => BigDecimal("1.29"),
    "Api::V1::IdentityController#show:emergency"    => BigDecimal("1.29"),

    # ── Verification ($1.49) ──
    "Api::V1::IdentityController#show"              => BigDecimal("1.49"),
    "Api::V1::TransactionConsentsController#create"  => BigDecimal("1.49"),
    "Api::V1::ConsentsController#request_consent"    => BigDecimal("1.49"),

    # ── Premium ($1.99) ──
    "Api::V1::VerificationsController#verify_identity" => BigDecimal("1.99"),
    "Api::V1::CrimeStatusController#show"            => BigDecimal("1.99"),
    "Api::V1::IncidentReportsController#index"       => BigDecimal("1.99"),
    "Api::V1::IncidentReportsController#certificate" => BigDecimal("1.99"),
    "Api::V1::OfficerComplaintsController#summary"   => BigDecimal("1.99")
  }.freeze

  # ── Scope-based cost overrides ──
  HEALTH_BIOMETRIC_SCOPES = %w[health physical].freeze
  CIVIL_SOCIAL_SCOPES     = %w[civil social emergency_contacts].freeze

  HEALTH_BIOMETRIC_COST = BigDecimal("0.99")
  CIVIL_SOCIAL_COST     = BigDecimal("1.29")

  # ── Crypto transaction type override ──
  CRYPTO_TRANSACTION_TYPES = %w[
    crypto_buy crypto_sell crypto_transfer crypto_swap crypto_kyc
  ].freeze

  CRYPTO_CREDIT_COST = BigDecimal("1.99")

  # ── Health-sector transaction types ──
  HEALTH_TRANSACTION_TYPES = %w[
    medical_consultation pharmacy_check insurance_claim
    health_screening organ_donor_check blood_type_check
  ].freeze

  # ── Civil-sector transaction types ──
  CIVIL_TRANSACTION_TYPES = %w[
    civil_registry family_verification inheritance_check
    social_trust_score emergency_contact_lookup lending_kyc
  ].freeze

  # Tier labels for the dashboard
  CREDIT_TIERS = {
    "Standard"           => { cost: BigDecimal("0.49"), endpoints: "QR scan, BonID status check, portal lookup" },
    "Health & Biometric" => { cost: BigDecimal("0.99"), endpoints: "Blood type, allergies, conditions, physical profile" },
    "Civil & Social"     => { cost: BigDecimal("1.29"), endpoints: "Family records, emergency contacts, social trust" },
    "Verification"       => { cost: BigDecimal("1.49"), endpoints: "Full identity, consent requests" },
    "Premium"            => { cost: BigDecimal("1.99"), endpoints: "Liveness, crime status, incident reports, crypto" }
  }.freeze

  # ============================================================
  # LOOKUPS
  # ============================================================
  def self.cost_for(controller_action_key, transaction_type: nil, scopes: nil)
    # Crypto transactions always cost Premium (199)
    return CRYPTO_CREDIT_COST if transaction_type.present? && CRYPTO_TRANSACTION_TYPES.include?(transaction_type)

    # Health-sector transaction types → 99 credits
    return HEALTH_BIOMETRIC_COST if transaction_type.present? && HEALTH_TRANSACTION_TYPES.include?(transaction_type)

    # Civil-sector transaction types → 129 credits
    return CIVIL_SOCIAL_COST if transaction_type.present? && CIVIL_TRANSACTION_TYPES.include?(transaction_type)

    # Scope-based overrides for consent/verification endpoints
    if scopes.present? && scopes.is_a?(Array)
      scopes_set = scopes.map(&:to_s)
      return HEALTH_BIOMETRIC_COST if (scopes_set - HEALTH_BIOMETRIC_SCOPES).empty? && scopes_set.any?
      return CIVIL_SOCIAL_COST if (scopes_set - CIVIL_SOCIAL_SCOPES).empty? && scopes_set.any?
    end

    CREDIT_COSTS.fetch(controller_action_key, 0)
  end

  def self.tier_for(controller_action_key)
    cost = cost_for(controller_action_key).to_d
    case
    when cost.zero?                                    then "Free"
    when cost <= BigDecimal("0.49")                    then "Standard"
    when cost <= BigDecimal("0.99")                    then "Health & Biometric"
    when cost <= BigDecimal("1.29")                    then "Civil & Social"
    when cost <= BigDecimal("1.49")                    then "Verification"
    else "Premium"
    end
  end

  # ============================================================
  # DISPLAY HELPERS
  # ============================================================
  def top_up?
    amount.positive?
  end

  def deduction?
    amount.negative?
  end

  def formatted_amount
    return "0 (free)" if amount.zero?
    formatted = sprintf("%.2f", amount.abs)
    top_up? ? "+#{formatted}" : "-#{formatted}"
  end

  def free_lookup?
    entry_type == "free_lookup"
  end

  def usd_equivalent
    amount.abs.to_d.round(2)
  end
end
