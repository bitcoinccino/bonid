# frozen_string_literal: true

require "openssl"
require "rqrcode"
require "chunky_png"
require "base64"
require "uri"

class Partner < ApplicationRecord
  include PartnerSectorConstants
  include PartnerRejectionConstants

  # ============================================================
  # ASSOCIATIONS
  # ============================================================
  belongs_to :admin_user, optional: true
  has_one_attached :logo
  has_one_attached :seal_image # Official partner seal/stamp for document signing
  has_one :address, as: :addressable, dependent: :destroy

  has_many :users, dependent: :nullify
  has_many :partner_admins, class_name: "User", foreign_key: "partner_id"
  has_many :officers, dependent: :nullify
  has_many :identity_submissions, dependent: :nullify
  has_many :partner_audit_logs, dependent: :nullify
  has_many :qr_scans, dependent: :nullify
  has_many :qr_scan_logs, dependent: :nullify
  has_many :partner_branches, dependent: :destroy
  has_many :agents, through: :partner_branches, source: :users
  has_many :incident_reports, dependent: :nullify
  has_many :api_access_logs, dependent: :destroy
  has_many :partner_schemas, dependent: :destroy
  has_many :service_applications, dependent: :destroy
  has_many :verification_records, dependent: :nullify
  has_one :oauth_application, dependent: :destroy
  has_many :consent_grants, dependent: :destroy
  has_many :transaction_consents, dependent: :destroy
  has_many :partner_api_logs, dependent: :destroy
  has_many :partner_payments, dependent: :destroy
  has_many :credit_ledger_entries, dependent: :destroy
  has_many :settlements, dependent: :destroy

  accepts_nested_attributes_for :address, update_only: true

  # Virtual attribute for form checkbox (not stored in DB)
  attr_accessor :terms_accepted

  # ============================================================
  # DELEGATIONS
  # ============================================================
  delegate :street_address, :communal_section, :commune, :arrondissement, :department,
           to: :address, allow_nil: true

  # ============================================================
  # ENUMS
  # ============================================================
  enum :status, { pending: 0, approved: 1, rejected: 2, suspended: 3 }, suffix: true

  # ============================================================
  # OAUTH CONSTANTS
  # ============================================================
  VALID_OAUTH_SCOPES = %w[
    openid
    profile
    email
    phone
    address
    physical
    health
    verifications:verify_identity
    identity:verify
    identity:details
    crime:status
    crime:reports
    crime:certificate
    crime:full
  ].freeze

  # API scope descriptions for documentation
  API_SCOPES_DESCRIPTION = {
    # Identity verification scopes
    "identity:verify" => "Verify BonID/BonTouris and check verification status",
    "identity:details" => "Access full identity details (name, DOB, address, photo)",

    # Crime status scopes
    "crime:status" => "Check crime involvement status for BonID/BonTouris holders",
    "crime:reports" => "Search and list incident reports involving a person",
    "crime:certificate" => "Generate and download official crime certificates",
    "crime:full" => "Full access to detailed crime records (requires citizen consent)"
  }.freeze

  # ============================================================
  # VALIDATIONS — CLEAN & SAFE
  # ============================================================
  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
  validates :api_key_digest, presence: true, if: :verified?

  validates :rejection_reason,
            inclusion: { in: PartnerRejectionConstants::REJECTION_REASONS.keys.map(&:to_s) },
            allow_nil: true,
            if: :rejected_status?

  # Terms checkbox (Rails checkboxes submit "1")
  validates :terms_accepted,
            acceptance: { accept: [ true, "1" ], message: "must be accepted" },
            on: :create

  # Webhook URL must be HTTPS (when provided)
  validates :webhook_url, format: { with: /\Ahttps:\/\//, message: "must be HTTPS" }, allow_blank: true

  # OAuth validations
  validate :validate_redirect_uri_format, if: -> { redirect_uris.present? }
  validate :validate_default_redirect_uri_in_list, if: -> { default_redirect_uri.present? }
  validate :validate_allowed_scopes_format, if: -> { allowed_scopes.present? }
  validate :validate_allowed_transaction_types_format, if: -> { allowed_transaction_types.present? }

  # ============================================================
  # CALLBACKS
  # ============================================================
  before_validation :set_slug, on: %i[create update]
  before_validation :set_sector_from_department, on: %i[create update]
  before_validation :set_default_oauth_scopes, on: :create
  before_validation :set_default_transaction_types, on: :create
  before_validation :ensure_default_redirect_uri, if: -> { redirect_uris.present? }
  before_create :generate_api_key_pair, unless: -> { Rails.env.test? }
  before_create :generate_email_verification_token

  # ============================================================
  # EMAIL VERIFICATION
  # ============================================================
  def generate_email_verification_token
    self.email_verification_token = SecureRandom.hex(32)
  end

  def verify_email!
    update!(
      email_verified_at: Time.current,
      email_verification_token: nil
    )
  end

  def email_verified?
    email_verified_at.present?
  end

  # ============================================================
  # SCOPES
  # ============================================================
  scope :active,       -> { where(active: true) }
  scope :verified,     -> { where.not(verified_at: nil) }
  scope :unverified,   -> { where(verified_at: nil) }
  scope :by_sector,    ->(sector) { where(sector: sector) }
  scope :kept,         -> { where(deleted_at: nil) }
  scope :only_deleted, -> { where.not(deleted_at: nil) }
  scope :with_deleted, -> { all }

  # ============================================================
  # GEOCODING
  # ============================================================
  geocoded_by :full_address
  after_validation :geocode, if: -> { Rails.env.production? && address.present? && address.changed? }

  # ============================================================
  # API KEY SYSTEM
  # ============================================================
  attr_reader :generated_api_key

  def generate_api_key_pair
    raw_key = "bonid_live_#{SecureRandom.hex(32)}"
    digest  = OpenSSL::Digest::SHA256.hexdigest(raw_key)
    self.api_key_digest = digest
    self.api_key_rotated_at = Time.current if respond_to?(:api_key_rotated_at)
    @generated_api_key = raw_key
  end

  def rotate_api_key!
    generate_api_key_pair
    save!
    @generated_api_key
  end

  def self.find_by_api_key(key)
    return nil if key.blank?

    digest = OpenSSL::Digest::SHA256.hexdigest(key)
    find_by(api_key_digest: digest)
  end

  def self.valid_api_key?(key)
    !!find_by_api_key(key)
  end

  # ============================================================
  # SECURITY SIGNING
  # ============================================================
  def sign_payload(payload)
    OpenSSL::HMAC.hexdigest("SHA256", api_key_digest.to_s, payload.to_json)
  end

  def verify_signature(payload, signature)
    expected = sign_payload(payload)
    ActiveSupport::SecurityUtils.secure_compare(signature, expected)
  end

  # ============================================================
  # WEBHOOK SUPPORT
  # ============================================================

  # Whether this partner can receive webhook notifications
  def webhook_enabled?
    webhook_url.present? && verified?
  end

  # HMAC-SHA256 signature for webhook payloads (using dedicated webhook_secret)
  def sign_webhook_payload(payload_json)
    return nil unless webhook_secret.present?
    OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, payload_json)
  end

  # Generate a new webhook secret for HMAC signing
  def generate_webhook_secret!
    update!(webhook_secret: SecureRandom.hex(32))
  end

  # ============================================================
  # OAUTH SECURITY METHODS
  # ============================================================

  # Check if a redirect URI is registered for this partner
  def valid_redirect_uri?(uri)
    return false if redirect_uris.blank? || uri.blank?

    normalized = normalize_uri(uri)
    registered = Array(redirect_uris).map { |u| normalize_uri(u) }

    registered.include?(normalized)
  end

  # Get the primary redirect URI
  def primary_redirect_uri
    default_redirect_uri || redirect_uris&.first
  end

  # ✅ Compatibility alias (prevents crashes in older code)
  def redirect_uri
    primary_redirect_uri
  end

  # Check if a scope is allowed for this partner
  def scope_allowed?(scope)
    return true if allowed_scopes.blank? # No restrictions
    allowed_scopes.include?(scope.to_s)
  end

  # Get effective allowed scopes (with fallback to all valid scopes)
  def effective_allowed_scopes
    allowed_scopes.presence || VALID_OAUTH_SCOPES
  end

  # Validate and filter requested scopes
  def filter_scopes(requested_scopes)
    scopes = Array(requested_scopes).map(&:to_s).compact.uniq
    scopes &= VALID_OAUTH_SCOPES
    scopes &= effective_allowed_scopes
    scopes.presence || %w[openid profile]
  end

  # ============================================================
  # TRANSACTION TYPE PERMISSIONS
  # ============================================================

  def transaction_type_allowed?(type)
    types = allowed_transaction_types
    return true if types.blank?
    types.include?(type.to_s)
  end

  def effective_allowed_transaction_types
    allowed_transaction_types.presence ||
      TransactionConsent.default_types_for_sector(sector)
  end

  # Add a new redirect URI
  def add_redirect_uri(uri)
    return false if uri.blank?

    normalized_uri = normalize_uri(uri)
    return false unless valid_uri_format?(normalized_uri)

    self.redirect_uris ||= []
    registered = Array(redirect_uris).map { |u| normalize_uri(u) }

    unless registered.include?(normalized_uri)
      self.redirect_uris = Array(redirect_uris) + [ normalized_uri ]
    end

    self.default_redirect_uri ||= normalized_uri
    save
  end

  # Remove a redirect URI
  def remove_redirect_uri(uri)
    return false if redirect_uris.blank? || uri.blank?

    target = normalize_uri(uri)
    self.redirect_uris = Array(redirect_uris).reject { |u| normalize_uri(u) == target }

    if default_redirect_uri.present? && normalize_uri(default_redirect_uri) == target
      self.default_redirect_uri = redirect_uris.first
    end

    save
  end

  # ============================================================
  # ADDRESS
  # ============================================================
  def full_address
    return nil unless address

    [
      street_address,
      communal_section&.name,
      commune&.name,
      arrondissement&.name,
      department&.name,
      "Haiti"
    ].compact.join(", ")
  end

  def full_name
    "#{contact_person} – #{name}"
  end

  def set_slug
    self.slug = name.parameterize if slug.blank? && name.present?
  end

  def verified?
    verified_at.present?
  end

  def suspended?
    suspended_at.present?
  end

  def deleted?
    deleted_at.present?
  end

  def active?
    verified?
  end

  def partner_admin_user
    users.joins(:roles).find_by(roles: { name: "partner_admin" })
  end

  # ============================================================
  # QR CODE GENERATION
  # ============================================================
  def qr_code_data_url(size = 200, padding = 4)
    return nil unless id.present?

    data = {
      partner_id: id,
      name: name,
      slug: slug,
      sector: sector,
      verified: verified?,
      api_hint: api_key_digest&.first(10)
    }.to_json

    qr = RQRCode::QRCode.new(data)

    qr_png = qr.as_png(
      size: size,
      border_modules: padding,
      color_mode: ChunkyPNG::COLOR_GRAYSCALE,
      fill: "white",
      color: "black"
    )

    qr_image = ChunkyPNG::Image.from_blob(qr_png.to_blob)

    if logo.attached?
      begin
        # Convert to PNG format and resize - ChunkyPNG only supports PNG
        logo_blob = logo.variant(
          resize_to_fit: [ size * 0.25, size * 0.25 ],
          format: :png
        ).processed.blob
        logo_image = ChunkyPNG::Image.from_blob(logo_blob.download)

        logo_x = (qr_image.width - logo_image.width) / 2
        logo_y = (qr_image.height - logo_image.height) / 2

        qr_image.replace!(logo_image, logo_x, logo_y)
      rescue ChunkyPNG::SignatureMismatch, StandardError => e
        # If logo processing fails, just return QR code without logo
        Rails.logger.warn("[Partner#qr_code_data_url] Logo processing failed for partner #{id}: #{e.message}")
      end
    end

    "data:image/png;base64,#{Base64.strict_encode64(qr_image.to_blob)}"
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  # ============================================================
  # CREDIT WALLET (Prepaid — like Natcom/Digicel recharge)
  # 1 Credit = $1.00 USD — stored as decimal(10,2)
  # ============================================================

  # Check if partner has enough credits for an API call
  def has_credits?(amount = BigDecimal("0.01"))
    credit_balance >= amount
  end

  # Deduct credits for an API call — atomic, creates ledger entry
  def deduct_credits!(amount:, endpoint_key:, description: nil, bonid: nil, ip_address: nil)
    return if amount <= 0

    transaction do
      reload # ensure fresh balance
      raise InsufficientCreditsError, "Balans ou a pa ase. Rechaje kont ou." if credit_balance < amount

      new_balance = credit_balance - amount
      update_column(:credit_balance, new_balance)

      credit_ledger_entries.create!(
        amount: -amount,
        balance_after: new_balance,
        entry_type: "deduction",
        endpoint_key: endpoint_key,
        description: description || CreditLedgerEntry.tier_for(endpoint_key),
        bonid: bonid,
        ip_address: ip_address
      )

      # Low balance alert — send once when crossing $5.00 threshold
      if new_balance < BigDecimal("5") && (new_balance + amount) >= BigDecimal("5")
        Partners::BillingMailer.low_balance_alert(self).deliver_later
      end
    end
  end

  # Top up credits — from payment (MonCash/Stripe) or admin bonus
  def top_up_credits!(amount:, payment_method: nil, transaction_id: nil, description: nil, entry_type: "top_up")
    raise ArgumentError, "Amount must be positive" unless amount.positive?

    transaction do
      reload
      new_balance = credit_balance + amount
      update_column(:credit_balance, new_balance)

      credit_ledger_entries.create!(
        amount: amount,
        balance_after: new_balance,
        entry_type: entry_type,
        payment_method: payment_method,
        transaction_id: transaction_id,
        description: description || "+$#{'%.2f' % amount} Credits (#{payment_method&.capitalize || 'Admin'})"
      )
    end
  end

  # ── Portal Lookup Daily Allowance ──
  # Partners get FREE_DAILY_PORTAL_LOOKUPS free lookups per day.
  # After that, each costs $0.49 (Standard tier).
  def portal_lookups_today
    credit_ledger_entries.portal_lookups.today.count
  end

  def free_portal_lookups_remaining
    [ CreditLedgerEntry::FREE_DAILY_PORTAL_LOOKUPS - portal_lookups_today, 0 ].max
  end

  def within_free_portal_allowance?
    portal_lookups_today < CreditLedgerEntry::FREE_DAILY_PORTAL_LOOKUPS
  end

  # Log a free portal lookup (0 cost, audit trail only)
  def log_free_portal_lookup!(bonid: nil, ip_address: nil)
    credit_ledger_entries.create!(
      amount: 0,
      balance_after: credit_balance,
      entry_type: "free_lookup",
      endpoint_key: CreditLedgerEntry::PORTAL_LOOKUP_ENDPOINT,
      description: "Portal Lookup (free #{portal_lookups_today}/#{CreditLedgerEntry::FREE_DAILY_PORTAL_LOOKUPS})",
      bonid: bonid,
      ip_address: ip_address
    )
  end

  # How many of each tier can the partner afford?
  def credit_purchasing_power
    bal = credit_balance.to_d
    {
      standard:      (bal / BigDecimal("0.49")).floor,
      health:        (bal / BigDecimal("0.99")).floor,
      civil:         (bal / BigDecimal("1.29")).floor,
      verifications: (bal / BigDecimal("1.49")).floor,
      premium:       (bal / BigDecimal("1.99")).floor
    }
  end

  # Credits used this month (for dashboard)
  def credits_used_this_month
    credit_ledger_entries.deductions.this_month.sum(:amount).abs
  end

  # Credits topped up this month
  def credits_added_this_month
    credit_ledger_entries.top_ups.this_month.sum(:amount)
  end

  class InsufficientCreditsError < StandardError; end

  # ============================================================
  # ANALYTICS
  # ============================================================
  def last_scan_at
    qr_scans.maximum(:scanned_at)
  end

  def has_branches?
    sector == "banking"
  end

  def safe_partner_branches
    has_branches? ? partner_branches : []
  end

  # ============================================================
  # CSV EXPORT
  # ============================================================
  def self.to_csv(partners)
    CSV.generate(headers: true) do |csv|
      csv << [
        "Partner Name", "Sector", "Total Citizens", "Total Scans", "Last Scan At",
        "Verified At", "Countries", "Regions", "Cities", "Organizations"
      ]

      partners.find_each do |p|
        scans = p.qr_scans
        csv << [
          p.name,
          p.sector&.titleize || "N/A",
          p.identity_submissions.distinct.count(:user_id),
          p.qr_scans.count,
          p.qr_scans.maximum(:scanned_at)&.strftime("%Y-%m-%d %H:%M"),
          p.verified_at&.strftime("%Y-%m-%d"),
          scans.distinct.pluck(:country).compact.join("; ").presence || "—",
          scans.distinct.pluck(:region).compact.join("; ").presence || "—",
          scans.distinct.pluck(:city).compact.join("; ").presence || "—",
          scans.distinct.pluck(:organization).compact.join("; ").presence || "—"
        ]
      end
    end
  end

  private

  # ============================================================
  # SECTOR DERIVATION
  # ============================================================
  # Maps department_sector (form value, e.g. "pnh") → sector
  # (value expected by PartnerSetupService, e.g. "law_enforcement").
  def set_sector_from_department
    return if department_sector.blank?
    return if sector.present? && !department_sector_changed?

    # Find which group this department_sector belongs to
    # e.g. "pnh" → "Law Enforcement", "banking" → "Finance"
    group = PartnerSectorConstants::SECTORS
              .find { |_group, values| values.include?(department_sector) }
              &.first

    # Law Enforcement is special: PartnerSetupService checks sector == "law_enforcement"
    # All other sectors use the raw department_sector value directly.
    self.sector = if group == "Law Enforcement"
                    "law_enforcement"
    else
                    department_sector
    end
  end

  # ============================================================
  # OAUTH VALIDATION METHODS
  # ============================================================
  def validate_redirect_uri_format
    return if redirect_uris.blank?

    redirect_uris.each do |uri|
      next if valid_uri_format?(uri)
      errors.add(:redirect_uris, "contains invalid or insecure URI: #{uri}")
    end
  end

  def validate_default_redirect_uri_in_list
    return if default_redirect_uri.blank? || redirect_uris.blank?

    normalized_default = normalize_uri(default_redirect_uri)
    normalized_list = Array(redirect_uris).map { |u| normalize_uri(u) }

    unless normalized_list.include?(normalized_default)
      errors.add(:default_redirect_uri, "must be one of the registered redirect URIs")
    end
  end

  def validate_allowed_scopes_format
    return if allowed_scopes.blank?

    invalid_scopes = allowed_scopes - VALID_OAUTH_SCOPES
    errors.add(:allowed_scopes, "contains invalid scopes: #{invalid_scopes.join(', ')}") if invalid_scopes.any?
  end

  def set_default_oauth_scopes
    self.allowed_scopes ||= VALID_OAUTH_SCOPES
  end

  def set_default_transaction_types
    self.allowed_transaction_types = TransactionConsent.default_types_for_sector(sector) if allowed_transaction_types.blank?
  end

  def validate_allowed_transaction_types_format
    return if allowed_transaction_types.blank?

    invalid = allowed_transaction_types - TransactionConsent::VALID_TRANSACTION_TYPES
    errors.add(:allowed_transaction_types, "contains invalid types: #{invalid.join(', ')}") if invalid.any?
  end

  def ensure_default_redirect_uri
    self.default_redirect_uri = redirect_uris.first if default_redirect_uri.blank? && redirect_uris.present?
  end

  def valid_uri_format?(uri)
    return false if uri.blank?

    parsed = URI.parse(uri)

    # Must be HTTP or HTTPS
    return false unless %w[http https].include?(parsed.scheme)

    # Prevent dangerous protocols
    return false if uri.match?(/^(javascript|data|file|vbscript):/i)

    # Must have a host
    return false if parsed.host.blank?

    true
  rescue URI::InvalidURIError
    false
  end

  # Normalize URIs before comparing/storing
  # - trims whitespace
  # - downcases host
  # - removes trailing slash (reduces mismatches)
  def normalize_uri(uri)
    raw = uri.to_s.strip
    return "" if raw.blank?

    parsed = URI.parse(raw)
    parsed.host = parsed.host.downcase if parsed.host

    normalized = parsed.to_s
    normalized.sub(%r{/\z}, "")
  rescue URI::InvalidURIError
    raw
  end
end
