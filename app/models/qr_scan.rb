class QrScan < ApplicationRecord
  # === Associations ===
  belongs_to :identity_submission
  belongs_to :partner, optional: true
  belongs_to :officer, optional: true
  belongs_to :partner_branch, optional: true
  belongs_to :department, optional: true
  belongs_to :banking_agent, class_name: "BankingAgent", optional: true

  has_many :qr_scan_logs, dependent: :destroy

  # === Attributes (Rails 8 typing) ===
  attribute :metadata, :json, default: {}
  attribute :status, :integer, default: 0
  attribute :scan_method, :integer, default: 0

  # === Enums (FIXED) ===
  enum :status, { success: 0, failed: 1 }, prefix: true
  enum :scan_method, { qr: 0, manual: 1 }, prefix: true

  # === Validations ===
  validates :identity_submission_id, presence: true
  validates :verified_by, presence: true
  validates :officer_id, presence: true, if: -> { verified_by == "Officer" }
  validates :partner_id, presence: true, if: -> { verified_by == "Partner" }

  before_create :set_geo_info
  before_validation :infer_scan_context

  # === Virtual helpers ===
  def partner_name
    partner&.name || "—"
  end

  def officer_name
    officer&.full_name || "—"
  end

  def branch_name
    partner_branch&.name || "—"
  end

  def department_name
    department&.name || partner_branch&.address&.department&.name || "—"
  end

  # === Export Helpers ===
  def self.to_csv
    CSV.generate(headers: true) do |csv|
      csv << [
        "BonID", "User", "Partner", "Branch", "Department",
        "Verified By", "Scan Method", "IP", "User Agent", "Scanned At"
      ]

      all.find_each do |scan|
        metadata = scan.metadata || {}
        csv << [
          scan.identity_submission&.bonid,
          scan.identity_submission&.user&.full_name,
          scan.partner_name,
          scan.branch_name,
          scan.department_name,
          scan.verified_by,
          scan.scan_method || "—",
          metadata["ip"],
          metadata["user_agent"],
          scan.created_at.strftime("%Y-%m-%d %H:%M:%S")
        ]
      end
    end
  end

  private

  # === Auto context inference (FIXED) ===
  def infer_scan_context
    if metadata&.dig("via") == "qr" || verified_by == "Officer"
      self.scan_method ||= "qr"
    elsif metadata&.dig("via") == "manual" || verified_by == "Partner"
      self.scan_method ||= "manual"
    end

    self.partner_branch ||= officer&.partner_branch if officer&.respond_to?(:partner_branch)
    self.department ||= partner_branch&.address&.department if partner_branch&.address&.department
  end

  def set_geo_info
    return if ip_address.blank?

    begin
      geo = Geocoder.search(ip_address).first
      self.country      = geo&.country.presence || "Unknown"
      self.city         = geo&.city.presence    || "Unknown"
      self.region       = geo&.state.presence   || "Unknown"
      self.organization = geo&.data.dig("org").presence
    rescue => e
      Rails.logger.warn "Geolocation lookup failed for #{ip_address}: #{e.message}"
    end
  end
end
