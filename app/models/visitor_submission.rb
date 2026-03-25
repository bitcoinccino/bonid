# frozen_string_literal: true

require "csv"
require "openssl"
require "base64"
require "rqrcode"

class VisitorSubmission < ApplicationRecord
  include BonidGenerator
  include RejectionReasons

  VISITOR_QR_VERSION = 1

  attr_accessor :affirm_information

  validates :affirm_information,
            acceptance: { accept: [ "1", true ] },
            on: :update

  # ============================================================
  # Associations
  # ============================================================
  belongs_to :user, optional: true

  has_one :address,
          as: :addressable,
          dependent: :destroy,
          inverse_of: :addressable

  has_one :local_contact, dependent: :destroy
  has_many :visitor_scan_events, dependent: :nullify


  # ============================================================
  # ActiveStorage
  # ============================================================
  has_one_attached :selfie
  has_one_attached :passport_photo

  # ============================================================
  # Nested attributes
  # ============================================================
  accepts_nested_attributes_for :address,
                                allow_destroy: true,
                                reject_if: ->(attrs) { attrs.values.all?(&:blank?) }

  accepts_nested_attributes_for :local_contact,
                                reject_if: ->(attrs) { attrs["name"].blank? && attrs["phone"].blank? }

  # ============================================================
  # Enums
  # ============================================================
  enum :entry_mode, { air: 0, sea: 1, land: 2 }, prefix: true

  enum :status, {
    pending_email_verification: 0,
    documents_required:         1,
    pending_review:             2,
    approved:                   3,
    rejected:                   4
  }, default: :pending_email_verification

  # ============================================================
  # Constants
  # ============================================================
  TITLES     = %w[Mr. Mrs. Miss Ms. Dr.].freeze
  PURPOSES   = %w[Tourism Business Official Transit Other].freeze
  OTP_EXPIRY = 10.minutes

  # Upload validation (user-facing)
  DOC_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    application/pdf
  ].freeze

  # PDF-safe image types (Prawn-compatible only)
  PDF_IMAGE_TYPES = %w[
    image/jpeg
    image/png
  ].freeze

  # ============================================================
  # Validations
  # ============================================================
  validates :title, inclusion: { in: TITLES }, allow_blank: true

  validates :first_name, :last_name, :dob, :sex,
            :passport_number, :purpose_of_visit,
            :entry_mode, :transport_provider,
            :port_of_entry, :residence_country,
            :nationality, presence: true

  validates :passport_number, uniqueness: { case_sensitive: false }

  validate :passport_not_expired
  validate :required_documents_present, if: :documents_or_later?
  validate :document_content_types,      if: :documents_or_later?

  # ============================================================
  # Callbacks
  # ============================================================
  before_validation :generate_visitor_bonid, on: :create
  before_validation :sync_country_code
  before_create     :set_expiry

  # ============================================================
  # Email OTP
  # ============================================================
  def generate_email_otp!
    update_columns(
      email_otp: SecureRandom.random_number(1_000_000).to_s.rjust(6, "0"),
      email_otp_sent_at: Time.current
    )
  end

  def email_otp_valid?(code)
    return false if email_otp.blank? || code.blank? || email_otp_sent_at.blank?
    return false if email_otp_sent_at <= OTP_EXPIRY.ago

    ActiveSupport::SecurityUtils.secure_compare(email_otp.to_s, code.to_s)
  end

  def mark_email_verified!
    updates = {
      email_verified_at: Time.current,
      email_otp: nil,
      updated_at: Time.current
    }

    updates[:status] = :documents_required if pending_email_verification?

    update_columns(updates)
  end

  def email_verified?
    email_verified_at.present?
  end

  # ============================================================
  # Document Submission
  # ============================================================
  def submit_documents!
    raise "Live selfie required" unless selfie.attached? && selfie_captured_at.present?
    raise "Passport photo required" unless passport_photo.attached?

    update!(status: :pending_review)
  end

  # ============================================================
  # BonTouris ID Generator
  # Format: T-JM-1968-M-US-P-884455-XDS
  #
  # Same HMAC checksum as BonID (last 3 chars).
  # Uses compute_bonid_checksum from BonidGenerator concern.
  # ============================================================
  def generate_visitor_bonid
    return if bonid.present?
    return unless validated_fields_for_bonid?

    initials = [
      first_name&.first,
      middle_name&.first,
      last_name&.first
    ].compact.map(&:upcase).join

    year   = dob.year
    gender = case sex.to_s.downcase
    when "male", "m"   then "M"
    when "female", "f" then "F"
    else "X"
    end

    country = nationality.to_s.upcase.first(2)

    passport_digits = passport_number.to_s.gsub(/\D/, "")
    last_six        = passport_digits.last(6).rjust(6, "0")

    base_code = "T-#{initials}-#{year}-#{gender}-#{country}-P-#{last_six}"
    checksum  = compute_visitor_checksum(base_code)

    self.bonid = "#{base_code}-#{checksum}"
  end

  # ============================================================
  # Offline checksum — extracted from BonTouris ID itself
  #
  # For IDs with HMAC checksum (8 segments): returns the checksum.
  # For legacy IDs (7 segments): computes from scratch.
  # ============================================================
  def offline_checksum
    segments = bonid.to_s.split("-")
    if segments.size >= 8
      segments.last.upcase
    else
      compute_visitor_checksum(bonid.to_s)
    end
  end

  # ============================================================
  # Visitor-specific HMAC checksum (alphanumeric only)
  #
  # Same HMAC-SHA256 as BonID but strips hyphens/underscores
  # from Base64URL output to avoid breaking segment delimiters.
  # ============================================================
  def compute_visitor_checksum(base_code)
    secret = Rails.application.credentials.dig(:bonid, :signature_secret)
    raise "Missing bonid.signature_secret in credentials" if secret.blank?

    digest = OpenSSL::HMAC.digest("SHA256", secret, base_code)
    base64 = Base64.urlsafe_encode64(digest, padding: false)
    base64.gsub(/[^A-Za-z0-9]/, "").first(3).upcase
  end

  # ============================================================
  # Verify BonTouris ID checksum (offline tamper detection)
  #
  # Example:
  #   vs.verify_visitor_checksum("T-DL-1988-M-US-P-885855-X9K")
  # ============================================================
  def verify_visitor_checksum(full_bonid = self.bonid)
    normalized = full_bonid.to_s.strip.upcase
    segments   = normalized.split("-")
    return false if segments.size < 8

    checksum  = segments.pop
    base_code = segments.join("-")
    expected  = compute_visitor_checksum(base_code)

    ActiveSupport::SecurityUtils.secure_compare(expected, checksum)
  rescue => e
    Rails.logger.error "⚠️ BonTouris verification failed: #{e.message}"
    false
  end

  # ============================================================
  # Backfill checksum for legacy BonTouris IDs (no checksum)
  # Call: VisitorSubmission.backfill_checksums!
  # ============================================================
  def self.backfill_checksums!
    where.not(bonid: nil).find_each do |vs|
      # Strip old bad checksum if present (with hyphens)
      segments = vs.bonid.to_s.split("-")
      base_code = if segments.size >= 8
        segments.first(7).join("-") # remove old checksum
      else
        vs.bonid
      end

      checksum = vs.compute_visitor_checksum(base_code)
      vs.update_column(:bonid, "#{base_code}-#{checksum}")
    end
  end

  # ============================================================
  # QR Code Generation (SINGLE FORMAT)
  #
  # ✅ Generates a QR image that encodes the SAME URL as your success page:
  #     /v?payload=BASE64URL(JSON)
  #
  # This supports:
  # - Online verification: open URL (Rails verifies)
  # - Offline verification: partner scans URL, verifies Ed25519 using public key
  #
  # NOTE: This method stores the QR PNG in visitor_qr_png_base64 for PDF/email use.
  # ============================================================
  def generate_visitor_qr!
    # Ensure BonTouris ID exists first
    generate_visitor_bonid if bonid.blank?

    # Use the exact same QR URL the success page uses (Ed25519 payload URL)
    url = VisitorCertificatePresenter.new(self).qr_payload
    raise "Missing QR payload URL" if url.blank?

    qr  = RQRCode::QRCode.new(url, level: :m)
    png = qr.as_png(size: 360)

    update!(visitor_qr_png_base64: Base64.strict_encode64(png.to_s))
  end

  # ============================================================
  # Approval (Admin)
  # ============================================================
  def approve!(admin:)
    raise ArgumentError, "Admin required" unless admin
    raise "Already approved" if approved?

    transaction do
      update!(status: :approved)

      generate_visitor_bonid if bonid.blank?
      generate_visitor_qr!   if visitor_qr_png_base64.blank?
    end

    begin
      VisitorMailer.with(visitor: self).welcome.deliver_later
    rescue => e
      Rails.logger.error(
        "[VisitorApproval] Email/PDF failed for VisitorSubmission##{id}: #{e.class} – #{e.message}"
      )
    end

    true
  end

  # ============================================================
  # Certificate Resend (Admin-only)
  # ============================================================
  def resend_certificate!
    raise "Not approved" unless approved?

    generate_visitor_bonid if bonid.blank?
    save! if bonid_changed?

    generate_visitor_qr! if visitor_qr_png_base64.blank?

    VisitorMailer.with(visitor: self).welcome.deliver_later
  end

  # ============================================================
  # Rejection (Admin)
  # ============================================================
  def reject!(admin:, reason:, notes: nil)
    raise ArgumentError, "Admin required" unless admin
    raise ArgumentError, "Invalid rejection reason" unless self.class.rejection_reasons.key?(reason.to_s)

    transaction do
      update!(
        status:               :rejected,
        rejection_reason:     reason,
        rejection_notes:      notes,
        rejected_at:          Time.current,
        rejected_by_admin_id: admin.id
      )

      VisitorMailer.with(visitor: self).rejected.deliver_later
    end
  end

  def rejection_reason_label
    return "Application issue" if rejection_reason.blank?

    I18n.t(
      "visitor.rejection_reasons.#{rejection_reason}",
      default: rejection_reason.to_s.humanize
    )
  end

  # ============================================================
  # Expiration
  # ============================================================
  def set_expiry
    self.expires_at ||= 90.days.from_now.end_of_day
  end

  # ============================================================
  # Stay Status Methods (for officer verification)
  # ============================================================

  # Returns number of days remaining until expires_at
  # Negative number means overstay
  def days_remaining
    return nil unless expires_at.present?
    (expires_at.to_date - Date.current).to_i
  end

  # Returns status symbol: :valid, :expiring_soon, :expires_today, :overstay
  def stay_status
    days = days_remaining
    return :unknown unless days

    case days
    when 8..Float::INFINITY then :valid
    when 1..7 then :expiring_soon
    when 0 then :expires_today
    else :overstay
    end
  end

  # Returns true if tourist has overstayed
  def overstay?
    days_remaining.present? && days_remaining.negative?
  end

  # Returns number of days overstayed (positive number)
  def overstay_days
    return 0 unless overstay?
    days_remaining.abs
  end

  # ============================================================
  # CSV Export
  # ============================================================
  def self.to_csv(scope)
    CSV.generate(headers: true) do |csv|
      csv << %w[id nationality sex dob entry_mode airline created_at]

      scope.find_each do |v|
        csv << [
          v.id,
          v.nationality,
          v.sex,
          v.dob,
          v.entry_mode,
          v.transport_provider,
          v.created_at.to_date
        ]
      end
    end
  end

  # ============================================================
  # Resume Application
  # ============================================================
  class << self
    def resume_for_email(email)
      normalized_email = email.to_s.downcase.strip
      return nil if normalized_email.blank?

      where("LOWER(email) = ?", normalized_email)
        .order(Arel.sql(<<~SQL))
          CASE status
            WHEN #{statuses[:pending_review]} THEN 1
            WHEN #{statuses[:documents_required]} THEN 2
            WHEN #{statuses[:pending_email_verification]} THEN 3
            ELSE 9
          END,
          updated_at DESC
        SQL
        .first
    end
  end

  # ============================================================
  # Analytics (Admin Dashboard)
  # ============================================================
  def self.analytics_by_department(scope = all)
    scope
      .joins(address: :department)
      .group("departments.name")
      .order("COUNT(visitor_submissions.id) DESC")
      .count
  end

  def self.analytics_by_accommodation(scope = all)
    scope
      .where.not(accommodation_type: [ nil, "" ])
      .group(:accommodation_type)
      .order("COUNT(id) DESC")
      .count
  end

  def self.analytics_by_entry_mode(scope = all)
    scope
      .group(:entry_mode)
      .order("COUNT(id) DESC")
      .count
      .transform_keys { |k| entry_modes.key(k) }
  end

  def self.analytics_by_nationality(scope = all)
    scope
      .where.not(nationality: [ nil, "" ])
      .group(:nationality)
      .order("COUNT(id) DESC")
      .count
  end

  def self.analytics_by_gender(scope = all)
    scope
      .where.not(sex: [ nil, "" ])
      .group(:sex)
      .order("COUNT(id) DESC")
      .count
      .transform_keys { |k| k.to_s.capitalize }
  end

  def self.analytics_by_age_group(scope = all)
    today = Date.current

    scope
      .where.not(dob: nil)
      .group(
        Arel.sql(<<~SQL.squish)
          CASE
            WHEN DATE_PART('year', AGE('#{today}', dob)) < 18 THEN 'Under 18'
            WHEN DATE_PART('year', AGE('#{today}', dob)) BETWEEN 18 AND 30 THEN '18–30'
            WHEN DATE_PART('year', AGE('#{today}', dob)) BETWEEN 31 AND 45 THEN '31–45'
            WHEN DATE_PART('year', AGE('#{today}', dob)) BETWEEN 46 AND 65 THEN '46–65'
            ELSE '65+'
          END
        SQL
      )
      .order("COUNT(id) DESC")
      .count
  end

  def self.analytics_by_season(scope = all)
    scope
      .where.not(created_at: nil)
      .group(
        Arel.sql(<<~SQL.squish)
          CASE
            WHEN EXTRACT(MONTH FROM created_at) IN (12,1,2) THEN 'Winter'
            WHEN EXTRACT(MONTH FROM created_at) IN (3,4,5) THEN 'Spring'
            WHEN EXTRACT(MONTH FROM created_at) IN (6,7,8) THEN 'Summer'
            ELSE 'Fall'
          END
        SQL
      )
      .order("COUNT(id) DESC")
      .count
  end

  def documents_or_later?
    documents_required? || pending_review? || approved? || rejected?
  end

  # ============================================================
  # Private
  # ============================================================
  private

  def qr_secret
    Rails.application.credentials.visitor_qr_secret || "visitor-qr-fallback"
  end

  def validated_fields_for_bonid?
    first_name.present? &&
      last_name.present? &&
      dob.present? &&
      sex.present? &&
      nationality.present? &&
      passport_number.present?
  end

  def passport_not_expired
    return if passport_expiry_date.blank?

    errors.add(:passport_expiry_date, "must be in the future") if passport_expiry_date <= Date.current
  end

  def required_documents_present
    errors.add(:selfie, "is required") unless selfie.attached?
    errors.add(:passport_photo, "is required") unless passport_photo.attached?
  end

  def document_content_types
    allowed = self.class::DOC_TYPES

    errors.add(:selfie, "invalid type") if selfie.attached? && !allowed.include?(selfie.content_type)
    errors.add(:passport_photo, "invalid type") if passport_photo.attached? && !allowed.include?(passport_photo.content_type)
  end

  def sync_country_code
    self.country_code ||= nationality
  end
end
