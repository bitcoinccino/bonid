# frozen_string_literal: true

class PartnerPayment < ApplicationRecord
  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :partner

  # ============================================================
  # ENUMS (string-backed for clarity)
  # ============================================================
  STATUSES       = %w[pending completed failed refunded].freeze
  PAYMENT_TYPES  = %w[top_up].freeze
  PAYMENT_METHODS = %w[moncash stripe].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :payment_type, inclusion: { in: PAYMENT_TYPES }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :order_id, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true

  # ============================================================
  # SCOPES
  # ============================================================
  scope :recent,      -> { order(created_at: :desc) }
  scope :successful,  -> { where(status: "completed") }
  scope :pending,     -> { where(status: "pending") }
  scope :failed,      -> { where(status: "failed") }
  scope :for_partner, ->(partner) { where(partner: partner) }
  scope :moncash,     -> { where(payment_method: "moncash") }
  scope :stripe,      -> { where(payment_method: "stripe") }
  scope :top_ups, -> { where(payment_type: "top_up") }

  # ============================================================
  # CALLBACKS
  # ============================================================
  before_validation :generate_order_id, on: :create, if: -> { order_id.blank? }

  # ============================================================
  # INSTANCE METHODS
  # ============================================================
  def completed?
    status == "completed"
  end

  def pending?
    status == "pending"
  end

  def failed?
    status == "failed"
  end

  def complete!(transaction_id: nil)
    update!(
      status: "completed",
      transaction_id: transaction_id,
      paid_at: Time.current
    )
  end

  def fail!(reason: nil)
    update!(
      status: "failed",
      failure_reason: reason
    )
  end

  def formatted_amount
    if currency == "HTG"
      "#{amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} HTG"
    else
      "$#{amount}"
    end
  end

  private

  def generate_order_id
    self.order_id = "BONID-#{SecureRandom.hex(8).upcase}-#{Time.current.strftime('%Y%m%d')}"
  end
end
