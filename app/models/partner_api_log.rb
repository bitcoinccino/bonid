# frozen_string_literal: true

class PartnerApiLog < ApplicationRecord
  belongs_to :partner, optional: true  # Optional to allow nil for unauthenticated logs

  # === Enums ===
  enum :log_status, {
    success: 0,
    failed: 1,
    timeout: 2
  }, prefix: true  # => log_status_success?, log_status_failed?, etc.

  # === Validations ===
  validates :endpoint, :request_method, :status_code, :requested_at, presence: true
  validates :request_method, inclusion: { in: %w[GET POST PUT PATCH DELETE] }
  validates :status_code,
            numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than: 600 }
  validates :response_time_ms,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :ip_address, length: { maximum: 45 }, allow_nil: true
  validates :user_agent, length: { maximum: 500 }, allow_nil: true

  # === Scopes ===
  scope :recent, -> { order(requested_at: :desc) }
  scope :successes, -> { where(log_status: :success) }
  scope :failures, -> { where(log_status: :failed) }
  scope :timeouts, -> { where(log_status: :timeout) }
  scope :for_partner, ->(partner_id) { where(partner_id: partner_id) if partner_id }
  scope :by_endpoint, ->(endpoint) { where("endpoint ILIKE ?", "%#{endpoint}%") if endpoint.present? }
  scope :date_range, ->(from, to) do
    q = all
    q = q.where("requested_at >= ?", from.to_date.beginning_of_day) if from.present?
    q = q.where("requested_at <= ?", to.to_date.end_of_day) if to.present?
    q
  end

  # === Callbacks ===
  after_create :set_log_status_from_code, if: :status_code_changed?

  private

  def set_log_status_from_code
    new_status =
      if status_code >= 500
        :failed
      elsif status_code >= 400
        :timeout # adjust as needed
      else
        :success
      end
    update!(log_status: new_status) if log_status != new_status
  end
end
