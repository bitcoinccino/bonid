# frozen_string_literal: true

# DgiPayment — Tracks citizen payments for DGI tax filings
# ==========================================================
# Supports MonCash, Natcash, bank transfer, and cash-at-window.
# Each payment is tied to a user and optionally to a VerificationRecord.
#
# Status lifecycle:
#   pending → processing → completed   (happy path)
#   pending → processing → failed      (provider error)
#   pending → expired                  (timeout)
#   completed → refunded               (admin action)
#
# For "cash_window" method:
#   pending → pending_cash → completed (DGI agent confirms in partner portal)
# ==========================================================

class DgiPayment < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================
  belongs_to :user
  belongs_to :verification_record, optional: true

  # ============================================================
  # Constants
  # ============================================================
  STATUSES        = %w[pending processing completed failed expired refunded pending_cash].freeze
  PAYMENT_METHODS = %w[moncash natcash zellus bank_transfer cash_window].freeze

  # BonGouv platform processing fee per form type (HTG)
  BONGOUV_FEES = {
    "nif_registration"        => 150.0,
    "business_registration"   => 250.0,
    "patente_declaration"     => 200.0,
    "tca_declaration"         => 150.0,
    "ras_ir_declaration"      => 150.0,
    "fermage"                 => 200.0,
    "election_registration"   => 0.0     # No BonGouv fee — DGI election fee only
  }.freeze

  # DGI official fees per form type (HTG)
  # Source: DGI Haiti / Loi de Finances 2021-2022
  # Election fees: Décret Électoral 1er Décembre 2025
  DGI_FEES = {
    "nif_registration"      => { base: 0, card: 1_000.0, label: "Kat Fiskal (CIF)" },
    "business_registration" => { base: 168.0, cip: 2_000.0, label: "Taks DGI + CIP" },
    "patente_declaration"   => { group_1: 5_000.0, group_2: 2_500.0, group_3: 1_250.0, label: "Dwa Fiks (pa komin)" },
    "tca_declaration"       => { base: 0, label: "Gratuit (taks 10% kalkile apa)" },
    "ras_ir_declaration"    => { base: 0, label: "Gratuit (retni kalkile apa)" },
    "fermage"               => { base: 0, label: "Dwa anyèl + Sitaks + DTP + Solidarite" },
    "election_registration" => {
      president: 800_000.0,
      senator: 120_000.0,
      deputy: 60_000.0,
      label: "Frè Enskripsyon Eleksyon (50% rediksyon: fanm, andikape, edikatè)"
    }
  }.freeze

  # Combined display fee: BonGouv fee + DGI base fee
  SERVICE_FEES = {
    "nif_registration"        => 1_150.0,   # 150 BonGouv + 1,000 Kat Fiskal
    "business_registration"   => 2_418.0,   # 250 BonGouv + 168 DGI + 2,000 CIP
    "patente_declaration"     => 200.0,     # 200 BonGouv (dwa fiks varies by commune)
    "tca_declaration"         => 150.0,     # 150 BonGouv (no DGI filing fee)
    "ras_ir_declaration"      => 150.0,     # 150 BonGouv (no DGI filing fee)
    "fermage"                 => 200.0,     # 200 BonGouv (tax varies by property)
    "election_registration"   => 0.0        # Fee varies by position (see DGI_FEES)
  }.freeze

  # Forms that require payment (tax forms with amounts due)
  PAYABLE_FORMS = %w[patente_declaration tca_declaration ras_ir_declaration fermage].freeze

  # Registration forms — fee-only (no tax amount calculated after)
  FEE_ONLY_FORMS = %w[nif_registration business_registration].freeze

  # ============================================================
  # Validations
  # ============================================================
  validates :status,         inclusion: { in: STATUSES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :order_id,       presence: true, uniqueness: true
  validates :amount_htg,     presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_htg,      presence: true, numericality: { greater_than: 0 }
  validates :currency,       presence: true

  # ============================================================
  # Scopes
  # ============================================================
  scope :recent,     -> { order(created_at: :desc) }
  scope :successful, -> { where(status: "completed") }
  scope :pending,    -> { where(status: %w[pending processing pending_cash]) }
  scope :for_user,   ->(user) { where(user: user) }
  scope :for_form,   ->(type) { where(form_type: type) }

  # ============================================================
  # URL Key — use order_id instead of numeric id
  # ============================================================
  def to_param
    order_id
  end

  # ============================================================
  # Callbacks
  # ============================================================
  before_validation :generate_order_id,  on: :create, if: -> { order_id.blank? }
  before_validation :calculate_total,    on: :create, if: -> { total_htg.blank? }

  # ============================================================
  # Status Methods
  # ============================================================
  def completed?  = status == "completed"
  def pending?    = %w[pending processing pending_cash].include?(status)
  def failed?     = status == "failed"
  def refunded?   = status == "refunded"

  def complete!(transaction_id: nil, provider_data: nil)
    update!(
      status: "completed",
      transaction_id: transaction_id,
      provider_response: provider_data || provider_response,
      paid_at: Time.current
    )

    # Sign the receipt with BonGouv's Ed25519 key → "Dokiman Otantik"
    sign_receipt!

    # Email the receipt to the citizen
    send_receipt_email!

    # Record in settlement ledger — tracks what BonID owes the partner
    SettlementService.record_payment(self)

  end

  # Generate the BonGouv digital seal for this receipt.
  # Called automatically on complete!, or manually for re-signing.
  def sign_receipt!
    Bongouv::ReceiptSigner.sign(self)
  rescue => e
    Rails.logger.error "[BonGouv] Receipt signing failed for payment #{id}: #{e.message}"
    nil
  end

  # Email the receipt to the citizen.
  # Called automatically on complete!, or manually for re-sending.
  def send_receipt_email!
    Bongouv::DgiMailer.payment_receipt(self).deliver_later
  rescue => e
    Rails.logger.error "[BonGouv] Receipt email failed for payment #{id}: #{e.message}"
  end

  # Check if this receipt has a valid BonGouv digital seal.
  def receipt_sealed?
    provider_response&.dig("bongouv_seal", "token").present?
  end

  # Verification token for the receipt QR code.
  def seal_token
    provider_response&.dig("bongouv_seal", "token")
  end

  # Full verification URL.
  def seal_verify_url
    token = seal_token
    return nil unless token
    "#{Bongouv::ReceiptSigner::VERIFY_BASE_URL}/#{token}"
  end

  def fail!(reason: nil)
    update!(status: "failed", failure_reason: reason)
  end

  def mark_processing!
    update!(status: "processing")
  end

  def mark_pending_cash!
    update!(status: "pending_cash")
  end

  # ============================================================
  # Display Helpers
  # ============================================================
  def formatted_total
    "#{total_htg.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} HTG"
  end

  def formatted_amount
    "#{amount_htg.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} HTG"
  end

  def payment_method_label
    case payment_method
    when "moncash"       then "MonCash"
    when "natcash"       then "Natcash"
    when "zellus"        then "Zellus"
    when "bank_transfer" then "Transfè Bankè"
    when "cash_window"   then "Kach nan Biwo DGI"
    end
  end

  def status_label
    case status
    when "pending"      then "Annatant"
    when "processing"   then "Ap trete..."
    when "completed"    then "Peye"
    when "failed"       then "Echwe"
    when "expired"      then "Ekspire"
    when "refunded"     then "Ranbouse"
    when "pending_cash" then "Annatant Kach"
    end
  end

  def status_badge_class
    case status
    when "completed"                        then "bg-success"
    when "pending", "processing"            then "bg-warning text-dark"
    when "pending_cash"                     then "bg-info"
    when "failed", "expired"               then "bg-danger"
    when "refunded"                         then "bg-secondary"
    end
  end

  def form_type_label
    case form_type
    when "nif_registration"      then "NIF (Formulaire A)"
    when "business_registration" then "Anrej. Biznis (Formulaire B)"
    when "patente_declaration"   then "Patant (DGI-F008)"
    when "tca_declaration"       then "TCA"
    when "ras_ir_declaration"    then "RAS IR (DGI-F005)"
    when "fermage"               then "Fèmaj (DGI-55)"
    when "election_registration" then "Frè Enskripsyon Eleksyon"
    end
  end

  # ============================================================
  # Class Methods
  # ============================================================
  def self.service_fee_for(form_type)
    SERVICE_FEES[form_type.to_s] || 150.0
  end

  def self.bongouv_fee_for(form_type)
    BONGOUV_FEES[form_type.to_s] || 150.0
  end

  def self.dgi_fee_info(form_type)
    DGI_FEES[form_type.to_s]
  end

  def self.requires_tax_payment?(form_type)
    PAYABLE_FORMS.include?(form_type.to_s)
  end

  private

  def generate_order_id
    self.order_id = "DGI-#{SecureRandom.hex(6).upcase}-#{Time.current.strftime('%Y%m%d')}"
  end

  def calculate_total
    self.fee_htg  ||= DgiPayment.service_fee_for(form_type)
    self.total_htg = (amount_htg || 0) + (fee_htg || 0)
  end
end
