# frozen_string_literal: true

class IdentitySubmission < ApplicationRecord
  require "rqrcode"
  require "base64"

  include DocumentIssuers
  include RejectionReasons

  # ==========================================================================
  # 🔐 ENCRYPTION (Rails 7+ Active Record Encryption)
  # ==========================================================================
  # Only encrypt HIGH-SENSITIVITY, NON-QUERY fields
  encrypts :ninu
  encrypts :id_number
  encrypts :cin_unique_id
  encrypts :document_issuer
  encrypts :reason
  encrypts :rejection_reason

  # === ENUMS ================================================================
  enum :submission_type, { initial: 0, resubmission: 1, reissue: 2,  visitor: 3  }, prefix: true
  enum :status,          { pending: 0, approved: 1, rejected: 2, revoked: 3 }, prefix: true
  enum :reset_request_status, { pending: "pending", approved: "approved", rejected: "rejected" }, prefix: true
  enum :staged_for, { none: 0, bonbin: 1, badbin: 2 }, prefix: true

  # === SCOPES ===============================================================
  scope :approved, -> { where(status: :approved) }
  scope :pending,  -> { where(status: :pending) }
  scope :rejected, -> { where(status: :rejected) }
  scope :revoked,  -> { where(status: :revoked) }

  ID_TYPES = {
    cin:      "Carte Identite National or CIN",
    passport: "Passport",
    license:  "Driver's License",
    voter_id: "Voter ID"
  }.freeze

  # BonID validity mirrors real Haitian document validity periods.
  # CIN = 10 yrs, Passport = 5 yrs, License = 5 yrs, Voter ID = 5 yrs.
  # Falls back to 5 years if id_type is unknown/nil.
  EXPIRY_BY_ID_TYPE = {
    "cin"      => 10.years,
    "passport" => 5.years,
    "license"  => 5.years,
    "voter_id" => 5.years
  }.freeze


  # === ASSOCIATIONS =========================================================
  belongs_to :user
  belongs_to :partner, optional: true
  belongs_to :reviewer, class_name: "User", foreign_key: "reviewer_id", optional: true
  belongs_to :reviewed_by_admin, class_name: "AdminUser", foreign_key: "reviewed_by_admin_id", optional: true

  has_many   :qr_scans, dependent: :destroy
  has_many   :qr_scan_logs, dependent: :destroy
  has_many   :signature_logs, dependent: :destroy

  # === ATTACHMENTS ==========================================================
  has_one_attached :photo
  has_one_attached :selfie
  has_one_attached :signature
  has_one_attached :cin_front
  has_one_attached :cin_back
  has_one_attached :passport
  has_one_attached :proof_of_address
  has_one_attached :digicel_phone_bill
  has_one_attached :natcom_phone_bill
  has_one_attached :baptismal_certificate
  has_one_attached :birth_certificate
  has_one_attached :adoption_certificate
  has_one_attached :naturalization_monitor_copy
  has_one_attached :archives_extract
  has_one_attached :pnh_record
  has_one_attached :bank_record
  has_one_attached :western_union_record
  has_one_attached :moneygram_record
  has_one_attached :sendwave_record
  has_one_attached :unitransfer_record
  has_one_attached :taptap_record
  has_one_attached :car_registration
  has_one_attached :car_rental_receipt
  has_one_attached :dinepa_bill
  has_one_attached :edh_bill
  has_one_attached :internet_bill
  has_one_attached :additional_proof
  has_one_attached :host_country_id          # Government-issued ID from country of residence (diaspora)
  has_one_attached :diaspora_proof_of_address # Proof of address in country of residence (utility bill, etc.)
  has_many_attached :liveness_audit_images   # Up to 4 AWS audit frames for gray-zone manual review

  has_secure_token :public_token

  # === LIFECYCLE HOOKS ======================================================
  before_validation :set_default_submission_type, on: :create
  before_validation :set_default_status,          on: :create
  before_validation :copy_user_photo_if_missing
  before_create     :generate_verification_token
  before_save       :set_reset_requested_at, if: :reset_request_status_pending?
  before_save       :set_staged_for_badbin,  if: -> { staged_for_badbin? }
  before_validation :skip_citizen_validations_for_visitor

  after_save    :set_verified_fields_if_approved
  after_update  :auto_link_verified_user_to_officer, if: -> { saved_change_to_status? && status_approved? }
  after_commit  :ensure_user_bonid_and_qr_if_approved, if: -> { status_approved? }
  after_commit  :regenerate_combined_qr_if_approved,   if: -> { status_approved? }
  after_commit :generate_secure_qr_if_approved, if: -> { saved_change_to_status? && status_approved? }
  after_commit :copy_selfie_to_user_photo, if: -> { saved_change_to_status? && status_approved? }


  # === VIRTUAL ATTRIBUTES ===================================================
  attr_accessor :skip_document_validations, :skip_single_active_check, :skip_liveness, :skip_signature
  delegate :first_name, :middle_name, :last_name, :dob, :sex, :marital_status, to: :user, allow_nil: true

  # === DIASPORA HELPER =========================================================
  def diaspora?
    country_of_residence.present? && country_of_residence != "HT"
  end

  # === SMART RESUBMISSION: DOCUMENT-ONLY REJECTIONS ==========================
  # These rejection reasons indicate document issues only — the citizen's
  # biometric identity (liveness + face match) is still valid and can be reused.
  DOCUMENT_ONLY_REJECTIONS = %w[
    blurry_documents incorrect_id expired_id
    invalid_proof_of_address expired_proof_of_address
    incomplete_submission non_haitian_id
  ].freeze

  # === VALIDATIONS ==========================================================
  validates :id_type,
          presence: true,
          inclusion: {
            in: IdentitySubmission::ID_TYPES.keys.map(&:to_s)
          },
          unless: :submission_type_visitor?

  # validates :id_type, presence: true, inclusion: { in: %w[cin passport] }
  validates :submission_type, presence: true, inclusion: { in: submission_types.keys }
  validates :reason, presence: true, if: -> { submission_type_reissue? }
  validates :rejection_reason, presence: true, if: -> { staged_for_badbin? }
  validates :status, presence: true
  validate  :single_active_submission, on: :create, unless: -> { skip_single_active_check }
  validates :user, presence: true, unless: :submission_type_visitor?
  # validates :id_type, presence: true, inclusion: { in: IdentitySubmission::ID_TYPES.keys }, unless: :submission_type_visitor?

  # === SELFIE (LIVENESS) VALIDATION ==========================================
  # The selfie blob comes from the liveness check — without it, face matching
  # cannot run and the submission is unverifiable. Block creation entirely.
  validate :selfie_must_be_attached, on: :create, unless: :submission_type_visitor?

  # === DOCUMENT NUMBER & EXPIRY VALIDATIONS ==================================
  validates :document_number,
            presence: { message: "Nimewo dokiman obligatwa" },
            if: -> { %w[cin passport].include?(id_type) && !submission_type_visitor? }

  validate :validate_document_number_format,
           if: -> { document_number.present? && %w[cin passport].include?(id_type) }

  validate :validate_document_not_expired,
           if: -> { document_expiry_date.present? }

  validate :validate_document_issue_date,
           if: -> { document_issue_date.present? }

  validate :validate_document_number_uniqueness,
           if: -> { document_number.present? && !submission_type_visitor? }

  # === DIASPORA VALIDATIONS =====================================================
  validates :country_of_residence, presence: true, unless: :submission_type_visitor?

  validates :host_country_id_type,
            presence: { message: "Tanpri endike ki kalite dokiman peyi rezidans ou." },
            if: :diaspora?

  validate :validate_host_country_id_attached, if: :diaspora?

  before_validation :normalize_document_number

  # === PARTNER HELPERS ======================================================
  def partner_name = partner&.name
  def partner_logo_url
    return unless partner&.logo&.attached?
    Rails.application.routes.url_helpers.rails_blob_url(partner.logo, only_path: true)
  end

  # === HMAC SIGNATURE =======================================================
  def hmac_signature_value
    return unless user&.bonid.present?
    secret = Rails.application.credentials.dig(:bonid, :signature_secret)
    return unless secret

    payload = { bonid: user.bonid, timestamp: verified_at.to_i.to_s }
    OpenSSL::HMAC.hexdigest("SHA256", secret, payload.to_json)
  end

  # === QR HELPERS ===========================================================
  def qr_for(role = :citizen)
    if role.to_sym.in?([ :officer, :admin ])
      secure_qr_png_base64
    else
      public_qr_png_base64.presence || secure_qr_png_base64
    end
  end



  def generate_public_qr!
    url = public_verify_url
    return if url.blank?

    qr = RQRCode::QRCode.new(url)
    png = qr.as_png(
      bit_depth: 1,
      border_modules: 4,
      color_mode: :rgb,
      color: "#00209F",    # Haitian Blue
      fill: "#FFFFFF",
      module_px_size: 6,
      size: 240
    )

    # IMPORTANT: write to the correct column your API expects
    if respond_to?(:qr_png_base64=)
      self.qr_png_base64 = Base64.strict_encode64(png.to_s)
    else
      self.public_qr_png_base64 = Base64.strict_encode64(png.to_s)
    end

    Rails.logger.info "✅ Public QR generated for submission #{id} (#{url})"
  rescue => e
    Rails.logger.error "[QR ERROR] Public QR generation failed for submission #{id}: #{e.class}: #{e.message}"
    nil
  end

  def public_verify_url
    helpers = Rails.application.routes.url_helpers

    raw_host =
      ENV["NGROK_HOST"].presence ||
      ENV["APP_HOST"].presence ||
      Rails.application.routes.default_url_options[:host].presence ||
      "127.0.0.1:3000"

    raw_host = raw_host.to_s.strip

    # Detect if it's ngrok and strip :3000
    is_ngrok = raw_host.include?("ngrok-free.app") || raw_host.include?("ngrok.io")

    host = raw_host.sub(%r{\Ahttps?://}i, "").sub(%r{/\z}, "")
    host = host.sub(/:3000\z/, "") if is_ngrok

    protocol = (raw_host.start_with?("https://") || is_ngrok) ? "https" : "http"

    helpers.verify_citizens_identity_submissions_url(
      verification_token: verification_token,
      host: host,
      protocol: protocol
    )
  end




  def generate_secure_qr!
    raise "Missing verification token" if verification_token.blank?
    return unless user&.bonid.present?

    payload = BonidQrSigner.sign(
      bonid: user.bonid,
      expires_at: expires_at || calculated_expires_at
    )

    qr  = RQRCode::QRCode.new(payload.to_json)
    png = qr.as_png(bit_depth: 1, border_modules: 4, color_mode: :rgb,
                    color: "#6B7280", fill: "#FFFFFF", module_px_size: 6, size: 240)
    self.secure_qr_png_base64 = Base64.strict_encode64(png.to_s)
  rescue => e
    Rails.logger.error("[QR ERROR] Secure QR generation failed for submission #{id}: #{e.message}")
  end

  # === CITIZEN QR ROTATION (60s auto-refresh) ==============================
  # Rotate ONLY the public verification QR used by citizens.
  # - Generates a NEW verification_token
  # - Regenerates the public QR PNG
  # - Does NOT touch expires_at (keeps 1-year validity from approval)
  def rotate_qr_for_citizen!
    transaction do
      self.verification_token = SecureRandom.hex(20)
      generate_public_qr!
      save!(validate: false)
    end
  rescue => e
    Rails.logger.error "[QR ERROR] Citizen QR rotation failed for submission #{id}: #{e.message}"
    false
  end


# === Secure QR Payload with Offline Verifiability ==========================
# Generates a cryptographically signed JSON payload for QR codes.
# Uses Ed25519 asymmetric signing — partners verify with public key only.
def generate_secure_qr_payload
  return {} unless user&.bonid.present?

  BonidQrSigner.sign(
    bonid: user.bonid,
    expires_at: expires_at || calculated_expires_at
  )
end



# === Auto QR Generation After Approval =====================================
def generate_secure_qr_if_approved
  return unless status_approved? && bonid.present?
  return if @qr_generating # Prevent recursive callback loop

  @qr_generating = true
  begin
    # --- 1. Compute or refresh verification timestamp ---
    self.verified_at ||= Time.current

    # --- 2. Build Ed25519-signed payload ---
    payload = BonidQrSigner.sign(
      bonid: user.bonid,
      expires_at: expires_at || calculated_expires_at
    )

    # Reuse hmac_signature_value column to store the Ed25519 sig (avoids migration)
    update_column(:hmac_signature_value, payload["sig"])
    Rails.logger.info "🔐 Ed25519 signature generated for BonID #{bonid}"

    # --- 3. Generate QR PNG ---
    qr  = RQRCode::QRCode.new(payload.to_json)
    png = qr.as_png(
      size: 240,
      border_modules: 4,
      color_mode: :rgb,
      color: "#04328C",
      fill: "#FFFFFF"
    )

    # --- 4. Persist encoded QR ---
    update_column(:secure_qr_png_base64, Base64.strict_encode64(png.to_s))
    Rails.logger.info "✅ Secure QR regenerated for BonID #{bonid}"

  rescue => e
    Rails.logger.error "❌ Failed to auto-generate secure QR for BonID #{bonid}: #{e.message}"
  ensure
    @qr_generating = false
  end
end


# === Delegated Payload + Verification =====================================
# Delegates to the User model for consistency with identity-based QR logic.
def generate_secure_qr_payload_from_user
  user&.generate_qr_payload || {}
end

def verify_qr_payload(payload)
  # Parse JSON if string
  payload = JSON.parse(payload) if payload.is_a?(String)

  # --- Ed25519 v2 payload ---
  if payload["v"].to_i == 2 && payload["sig"].present?
    result = BonidQrSigner.verify(payload)
    return result == :valid
  end

  # --- Legacy HMAC fallback (v1 / unversioned) ---
  bonid_value = payload["bonid"] || payload[:bonid]
  ts          = payload["timestamp"] || payload[:timestamp]
  sig         = payload["signature"] || payload[:signature]

  return false unless bonid_value == bonid
  return false if Time.now.to_i - ts.to_i > 900 # 15-minute validity window

  ActiveSupport::SecurityUtils.secure_compare(sig, user.qr_signature(ts.to_i))
rescue => e
  Rails.logger.error "⚠️ QR verification failed for BonID #{bonid}: #{e.message}"
  false
end


  # === EXPIRY HELPERS =========================================================
  # Returns the correct ActiveSupport::Duration for this submission's id_type.
  # Used everywhere expires_at is calculated so expiry is always consistent.
  def expiry_duration
    EXPIRY_BY_ID_TYPE.fetch(id_type.to_s, 5.years)
  end

  # Convenience: absolute timestamp from now
  def calculated_expires_at
    expiry_duration.from_now
  end

  # === VERIFICATION =========================================================
  def verified? = status_approved? && verified_at.present? && expires_at&.future?
  def qr_expired? = expires_at.present? && expires_at.past?

  def mark_as_verified!
    transaction do
      update!(status: :approved, verified_at: Time.current, expires_at: calculated_expires_at)
      user.update!(bonid: user.generate_bonid!) if user.bonid.blank?
      PersonInvolvement.where(user_id: nil, bonid: user.bonid).update_all(user_id: user.id)
      regenerate_combined_qr!
    end
  end

  # === COMBINED QR ==========================================================
  def regenerate_combined_qr!
    return false if @regenerating_qr # Guard against infinite recursion
    @regenerating_qr = true

    transaction do
      self.verification_token ||= SecureRandom.hex(20)
      # Preserve existing expiry if already set; otherwise calculate from id_type
      self.expires_at = expires_at.presence || calculated_expires_at
      generate_public_qr!
      generate_secure_qr!

      # ✅ Skip validations to prevent rollback on old or visitor submissions
      save(validate: false)
    end
  rescue => e
    Rails.logger.error("[QR ERROR] Failed to regenerate combined QR for submission #{id}: #{e.message}")
    false
  ensure
    @regenerating_qr = false
  end

  def regenerate_combined_qr_if_approved
    regenerate_combined_qr! if saved_change_to_status? && status_approved?
  end

  # === LOOKUP / IDENTIFIERS ================================================
  def certificate_number = "BONID-#{created_at.year}-#{id.to_s.rjust(5, '0')}"

    def verification_qr_url
      helpers = Rails.application.routes.url_helpers

      raw_host =
        ENV["NGROK_HOST"].presence ||
        ENV["APP_HOST"].presence ||
        Rails.application.routes.default_url_options[:host].presence ||
        "127.0.0.1:3000"

      # helpers expect host WITHOUT scheme
      host = raw_host.to_s.sub(%r{\Ahttps?://}i, "").sub(%r{/\z}, "")

      protocol =
        raw_host.to_s.start_with?("https://") || ENV["NGROK_HOST"].present? ? "https" : "http"

      helpers.verify_citizens_identity_submissions_url(
        verification_token: verification_token,
        host: host,
        protocol: protocol
      )
    end



  def selfie_url
    Rails.application.routes.url_helpers.rails_blob_url(selfie, only_path: true) if selfie.attached?
  end

  # === DOCUMENTS ============================================================
  def primary_documents = [ cin_front, cin_back, passport ].select(&:attached?)

  def selfie_document
    selfie if selfie.attached?
  end

  def secondary_documents
    [
      proof_of_address, digicel_phone_bill, natcom_phone_bill, baptismal_certificate,
      birth_certificate, adoption_certificate, naturalization_monitor_copy, archives_extract,
      pnh_record, bank_record, western_union_record, moneygram_record, sendwave_record,
      unitransfer_record, taptap_record, car_registration, additional_proof
    ].select(&:attached?)
  end

  def missing_documents
    [].tap do |missing|
      missing << "selfie" unless selfie.attached?
      missing << "signature" unless signature.attached?
      missing << "ID (CIN or Passport)" unless cin_front.attached? || passport.attached?
      missing << "proof of address" unless proof_of_address.attached? ||
                                          digicel_phone_bill.attached? ||
                                          natcom_phone_bill.attached?
    end
  end

  def ready_for_approval? = missing_documents.empty?

  # === FACE MATCH HELPERS ===================================================
  def face_match_result     = metadata&.dig("face_match")
  def face_match_status     = face_match_result&.dig("status")
  def face_match_similarity = face_match_result&.dig("similarity")
  def face_matched?         = face_match_status == "match"
  def face_match_flagged?   = face_match_status.in?(%w[no_match no_face_detected error])

  # === SMART RESUBMISSION ===================================================
  # Returns true if this rejected submission's biometrics (liveness + face match)
  # can be carried forward to a new submission, avoiding redundant AWS API calls.
  # Only safe when the rejection was for a document issue, NOT a biometric failure.
  def biometrics_reusable?
    return false unless status_rejected?
    return false unless rejection_reason.in?(DOCUMENT_ONLY_REJECTIONS)
    return false unless metadata&.dig("liveness", "passed") == true
    return false unless metadata&.dig("face_match", "status") == "match"
    return false unless (metadata&.dig("face_match", "similarity") || 0) >= FaceMatchService::SIMILARITY_THRESHOLD
    return false unless selfie.attached? && selfie.blob.present?
    true
  end

  # Returns true if this rejected submission's signature can be carried forward.
  # Safe when rejection was document-only and signature blob still exists.
  def signature_reusable?
    return false unless status_rejected?
    return false unless rejection_reason.in?(DOCUMENT_ONLY_REJECTIONS)
    return false unless signature.attached? && signature.blob.present?
    true
  end

  # === OFFICER LINKING ======================================================
  def auto_link_verified_user_to_officer
    return unless user.present? && user.email.present?
    officer = Officer.find_by(email: user.email)
    return if officer.blank? || officer.user_id.present?

    officer.update(user_id: user.id)
    Rails.logger.info "🔗 Linked Officer ##{officer.id} to User ##{user.id} after BonID approval"
  rescue => e
    Rails.logger.error "❌ auto_link_verified_user_to_officer failed: #{e.message}"
  end

  # === PRIVATE HELPERS ======================================================
  private

  # ── Document number / expiry validations ──────────────────────────────────

  def normalize_document_number
    self.document_number = CinNumberValidator.normalize(document_number) if document_number.present?
  end

  def selfie_must_be_attached
    return if selfie.attached?
    # Allow if biometrics are being carried forward from a previous submission
    return if respond_to?(:skip_single_active_check) && metadata&.dig("liveness", "reused")
    errors.add(:selfie, "Ou dwe fè verifikasyon figi (liveness) anvan ou soumèt.")
  end

  def validate_document_number_format
    unless CinNumberValidator.valid?(document_number, id_type)
      case id_type
      when "cin"
        errors.add(:document_number, "Nimewo CIN pa valid. Dwe gen 10, 14, oswa 17 chif.")
      when "passport"
        errors.add(:document_number, "Nimewo paspò pa valid. Dwe gen 6–9 karaktè.")
      end
    end
  end

  def validate_document_not_expired
    if document_expiry_date < Date.current
      errors.add(:document_expiry_date, "Dokiman ekspire. Ou pa ka itilize yon dokiman ki ekspire.")
    end
  end

  def validate_document_issue_date
    if document_issue_date > Date.current
      errors.add(:document_issue_date, "Dat emisyon pa ka nan lavni.")
    end
  end

  def validate_document_number_uniqueness
    existing = IdentitySubmission
      .where(document_number: document_number)
      .where(status: :approved)
      .where.not(user_id: user_id)
    existing = existing.where.not(id: id) if persisted?

    if existing.exists?
      errors.add(:document_number, "Nimewo dokiman sa a deja anrejistre ak yon lòt kont BonID.")
    end
  end

  def validate_host_country_id_attached
    unless host_country_id.attached?
      errors.add(:host_country_id, "Tanpri upload dokiman idantite peyi kote ou ap viv la.")
    end
  end

  # ── End document validations ──────────────────────────────────────────────

  def ensure_user_bonid_and_qr_if_approved
    return unless user.present?
    return if @regenerating_qr # Don't re-enter during QR regeneration

    user.generate_bonid! if user.bonid.blank?
    update_column(:bonid, user.bonid) if bonid.blank?
    update_columns(
      verified_at: (verified_at || Time.current),
      expires_at:  (expires_at || calculated_expires_at)
    )
    regenerate_combined_qr! if public_qr_png_base64.blank? || secure_qr_png_base64.blank?
  rescue => e
    Rails.logger.error "❌ ensure_user_bonid_and_qr_if_approved failed: #{e.message}"
  end

  def single_active_submission
    return unless user
    if user.identity_submissions.status_approved.exists?
      errors.add(:base, "User already has an active identity submission.")
    end
  end

  def copy_user_photo_if_missing
    return if photo.attached?
    return unless user&.photo&.attached?
    photo.attach(user.photo.blob)
  rescue => e
    Rails.logger.warn "⚠️ Failed to copy user photo to submission: #{e.message}"
  end

  def set_default_submission_type
    self.submission_type ||= "initial"
  end

  def set_default_status
    self.status ||= :pending
  end

  def generate_verification_token
    self.verification_token ||= SecureRandom.hex(16)
  end

  def set_reset_requested_at
    self.reset_requested_at ||= Time.current if reset_request_status_pending?
  end

  def set_staged_for_badbin
    self.staged_for = :badbin if rejection_reason == "bad_bin"
  end

  # === AUTO-POPULATE USER PHOTO FROM APPROVED SELFIE ========================
  # When a submission is approved, copy the verified selfie to the user's
  # profile photo. This ensures API consistency since the selfie has been
  # validated by an admin during the approval process.
  def copy_selfie_to_user_photo
    return unless user.present? && selfie.attached?

    user.photo.attach(selfie.blob)
    Rails.logger.info "📸 Copied approved selfie to user photo for User ##{user.id}"
  rescue => e
    Rails.logger.error "❌ Failed to copy selfie to user photo: #{e.message}"
  end

  def set_verified_fields_if_approved
    return unless saved_change_to_status? && status_approved?
    update_columns(
      verified_at: (verified_at || Time.current),
      expires_at:  (expires_at || calculated_expires_at)
    )
  rescue => e
    Rails.logger.error "⚠️ Failed to set verified fields: #{e.message}"
  end

  def skip_citizen_validations_for_visitor
    return unless submission_type_visitor?
    self.user_id = nil        # visitors aren’t users
    self.id_type = "passport" # fallback for visitors
  end
end


# # app/models/identity_submission.rb
# class IdentitySubmission < ApplicationRecord
#   require "rqrcode"
#   require "base64"

#   belongs_to :user
#   belongs_to :partner, optional: true

#   has_many :qr_scans, dependent: :destroy
#   has_many :qr_scan_logs, dependent: :destroy  # ✅ keep only once

#   # === Attachments ===
#   has_one_attached :signature
#   has_one_attached :cin_front
#   has_one_attached :cin_back
#   has_one_attached :passport
#   has_one_attached :selfie
#   has_one_attached :proof_of_address
#   has_one_attached :digicel_phone_bill
#   has_one_attached :natcom_phone_bill
#   has_one_attached :baptismal_certificate
#   has_one_attached :birth_certificate
#   has_one_attached :adoption_certificate
#   has_one_attached :naturalization_monitor_copy
#   has_one_attached :archives_extract
#   has_one_attached :pnh_record
#   has_one_attached :bank_record
#   has_one_attached :western_union_record
#   has_one_attached :moneygram_record
#   has_one_attached :sendwave_record
#   has_one_attached :unitransfer_record
#   has_one_attached :taptap_record
#   has_one_attached :car_registration
#   has_one_attached :additional_proof

#   # === Enums ===
#   enum status: { pending: 0, approved: 1, rejected: 2, revoked: 3 }
#   enum submission_type: { initial: "initial", resubmission: "resubmission", reissue: "reissue" }
#   enum reset_request_status: { pending: 0, approved: 1, rejected: 2 }, prefix: :reset_request_status
#   enum staged_for: { none: 0, bonbin: 1, badbin: 2 }, prefix: :staged_for

#   # === Lifecycle Hooks ===
#   before_validation :set_default_submission_type, on: :create
#   before_validation :set_default_status, on: :create
#   before_validation :copy_user_photo_if_missing
#   before_create :generate_verification_token
#   before_save :set_reset_requested_at, if: :reset_request_status_pending?
#   before_save :set_staged_for_badbin, if: -> { staged_for_badbin? }
#   before_save :assign_bonid_from_user, if: -> { approved? && bonid.blank? }
#   after_save :set_verified_fields_if_approved
#   after_update :regenerate_combined_qr_if_approved
#   after_update :auto_link_verified_user_to_officer, if: -> { saved_change_to_status? && approved? }
#   after_commit :ensure_user_bonid_and_qr_if_approved, if: -> { approved? }
#   after_commit :ensure_dual_qrs_if_approved, if: -> { approved? }

#   # === Virtual attributes ===
#   attr_accessor :skip_document_validations, :skip_single_active_check

#   # === Validations ===
#   validates :id_type, presence: true, inclusion: { in: %w[cin passport] }
#   validates :submission_type, presence: true, inclusion: { in: submission_types.keys }
#   validates :reason, presence: true, if: -> { submission_type == "reissue" }
#   validates :rejection_reason, presence: true, if: -> { staged_for_badbin? }
#   validate :single_active_submission, on: :create, unless: -> { skip_single_active_check }

#   # === Partner Helpers ===
#   def partner_name
#     partner&.name
#   end

#   def partner_logo_url
#     return nil unless partner&.logo&.attached?
#     Rails.application.routes.url_helpers.rails_blob_url(partner.logo, only_path: true)
#   end

#   # === HMAC Signature Helper ===
#   def hmac_signature_value
#     return nil unless user&.bonid.present?
#     secret_key = Rails.application.credentials.dig(:bonid, :signature_secret)
#     return nil unless secret_key.present?

#     payload = { bonid: user.bonid, timestamp: verified_at.to_i.to_s }
#     OpenSSL::HMAC.hexdigest("SHA256", secret_key, payload.to_json)
#   end

#   # === QR Helpers ===
#   def qr_for(role = :citizen)
#     case role.to_sym
#     when :officer, :admin
#       secure_qr_png_base64
#     else
#       public_qr_png_base64
#     end
#   end

#   def generate_qr_png_base64
#     public_qr_png_base64 || secure_qr_png_base64
#   end

#   # === Rejection Reasons (for Admin UI) ===
#   def self.rejection_reasons_options
#     {
#       "ID Issues" => [
#         [ "Missing ID document: Upload a valid CIN (front and back) or Passport", "missing_id" ],
#         [ "Blurry or unreadable ID photo", "blurry_id" ],
#         [ "Expired ID document", "expired_id" ],
#         [ "Non-Haitian ID submitted", "non_haitian_id" ],
#         [ "Name mismatch on ID", "name_mismatch_id" ],
#         [ "Suspected tampering with ID", "tampered_id" ]
#       ],
#       "Selfie Issues" => [
#         [ "Missing selfie", "missing_selfie" ],
#         [ "Blurry selfie", "blurry_selfie" ],
#         [ "Selfie doesn’t match ID", "selfie_mismatch" ],
#         [ "AI-altered selfie", "ai_altered_selfie" ]
#       ],
#       "Proof of Address Issues" => [
#         [ "Missing proof of address", "missing_proof" ],
#         [ "Invalid proof of address", "invalid_proof" ],
#         [ "Outdated proof of address", "outdated_proof" ]
#       ],
#       "Consistency Issues" => [
#         [ "Inconsistent information", "inconsistent_info" ],
#         [ "Low-quality uploads", "low_quality_uploads" ],
#         [ "Conflicting submissions", "conflicting_submissions" ],
#         [ "Duplicate submission", "duplicate_submission" ],
#         [ "Identity could not be verified", "unverified_identity" ],
#         [ "Incomplete submission", "incomplete_submission" ]
#       ],
#       "Other" => [ [ "Other: Please specify below", "other" ] ]
#     }
#   end

#   # === Submission Type Helpers ===
#   def self.assign_submission_type_for(user)
#     last = user.identity_submissions.order(created_at: :desc).first
#     return "initial" if last.nil?
#     return "resubmission" if last.status_rejected?
#     return "reissue" if last.status_approved?
#     "initial"
#   end

#   def assign_submission_type(user)
#     last = user.identity_submissions.order(created_at: :desc).first
#     case last&.status
#     when nil then "initial"
#     when "rejected" then "resubmission"
#     when "approved" then "reissue"
#     else "initial"
#     end
#   end

#   # === Lookup Helpers ===
#   def self.find_user_and_submission_by_bonid(bonid)
#     submission = approved.find_by(bonid: bonid)
#     [ submission&.user, submission ]
#   end

#   def selfie_url
#     Rails.application.routes.url_helpers.rails_blob_url(selfie, only_path: true) if selfie.attached?
#   end

#   # === Status Helpers ===
#   def verified?
#     approved? && verified_at.present? && expires_at.present? && expires_at.future?
#   end

#   def qr_expired?
#     expires_at.present? && expires_at.past?
#   end

#   # === Verification lifecycle ===
#   def mark_as_verified!
#     transaction do
#       # ✅ Citizen-facing QR expires in 5 minutes
#       update!(status: :approved, verified_at: Time.current, expires_at: 5.minutes.from_now)
#       user.update!(bonid: user.generate_bonid!) if user.bonid.blank?
#       PersonInvolvement.where(user_id: nil, bonid: user.bonid).update_all(user_id: user.id)
#       regenerate_combined_qr!
#     end
#   end

#   def mark_verified!
#     update!(verified_at: Time.current)
#   end

#   def assign_bonid_from_user
#     self.bonid = user.bonid if user&.bonid.present?
#   end

#   def certificate_number
#     "BONID-#{created_at.year}-#{id.to_s.rjust(5, '0')}"
#   end

#   # === Verification URL (for public QR) ===
#   def verification_qr_url
#     Rails.application.routes.url_helpers.verify_identity_submission_url(
#       verification_token: verification_token,
#       host: Rails.application.routes.default_url_options[:host]
#     )
#   end

#   # === Public QR (citizens) ===
#   def generate_public_qr!
#     qr = RQRCode::QRCode.new(verification_qr_url)
#     png = qr.as_png(
#       bit_depth: 1,
#       border_modules: 4,
#       color_mode: :rgb,
#       color: "#00209F",
#       fill: "#FFFFFF",
#       module_px_size: 6,
#       size: 240
#     )
#     update_column(:public_qr_png_base64, Base64.strict_encode64(png.to_s))
#   end

#   # === Secure QR (officers/admins) ===
#   def generate_secure_qr!
#     raise "Missing verification token" if verification_token.blank?
#     return unless user&.bonid.present?

#     timestamp = Time.current.to_i
#     secret_key = Rails.application.credentials.dig(:bonid, :signature_secret)
#     raise "Missing bonid.signature_secret" unless secret_key.present?

#     payload_data = { bonid: user.bonid, timestamp: timestamp.to_s }
#     signature    = OpenSSL::HMAC.hexdigest("SHA256", secret_key, payload_data.to_json)
#     payload      = payload_data.merge(signature: signature, partner: partner&.slug)

#     qr = RQRCode::QRCode.new(payload.to_json)
#     png = qr.as_png(
#       bit_depth: 1,
#       border_modules: 4,
#       color_mode: :rgb,
#       color: "#6B7280",
#       fill: "#FFFFFF",
#       module_px_size: 6,
#       size: 240
#     )
#     update_column(:secure_qr_png_base64, Base64.strict_encode64(png.to_s))
#   end

#   # === Combined QR ===
#   def regenerate_combined_qr!
#     generate_public_qr!
#     generate_secure_qr!
#   end

#   def regenerate_combined_qr_if_approved
#     regenerate_combined_qr! if saved_change_to_status? && approved?
#   end

#   def ensure_dual_qrs_if_approved
#     generate_public_qr! if public_qr_png_base64.blank?
#     generate_secure_qr! if secure_qr_png_base64.blank?
#   end

#   # === Documents ===
#   def primary_documents
#     [].tap do |docs|
#       docs << cin_front if cin_front.attached?
#       docs << cin_back if cin_back.attached?
#       docs << passport if passport.attached?
#     end
#   end

#   def selfie_document
#     selfie if selfie.attached?
#   end

#   def secondary_documents
#     [
#       proof_of_address,
#       digicel_phone_bill,
#       natcom_phone_bill,
#       baptismal_certificate,
#       birth_certificate,
#       adoption_certificate,
#       naturalization_monitor_copy,
#       archives_extract,
#       pnh_record,
#       bank_record,
#       western_union_record,
#       moneygram_record,
#       sendwave_record,
#       unitransfer_record,
#       taptap_record,
#       car_registration,
#       additional_proof
#     ].select(&:attached?)
#   end

#   # === Validation Helpers ===
#   def single_active_submission
#     if user.identity_submissions.where(status: %i[pending approved]).exists?
#       errors.add(:base, "You already have a pending or approved submission.")
#     end
#   end

#   def required_documents_present
#     cin_complete = cin_front.attached? && cin_back.attached?
#     passport_present = passport.attached?
#     errors.add(:base, "You must upload both CIN Front and CIN Back OR a Passport.") unless cin_complete || passport_present
#     errors.add(:selfie, "must be attached.") unless selfie.attached?

#     unless [
#       digicel_phone_bill, natcom_phone_bill, baptismal_certificate, birth_certificate,
#       adoption_certificate, naturalization_monitor_copy, archives_extract, pnh_record,
#       bank_record, western_union_record, moneygram_record, sendwave_record,
#       unitransfer_record, taptap_record, additional_proof
#     ].any?(&:attached?)
#       errors.add(:base, "You must upload at least one supporting document.")
#     end
#   end

#   # === Officer Linking ===
#   def auto_link_verified_user_to_officer
#     return unless user.present? && user.email.present?
#     officer = Officer.find_by(email: user.email)
#     return if officer.blank? || officer.user_id.present?
#     officer.update(user_id: user.id)
#     Rails.logger.info "🔗 Linked Officer ##{officer.id} (#{officer.email}) to User ##{user.id} after BonID approval"
#   rescue => e
#     Rails.logger.error "❌ Failed to link Officer to User: #{e.message}"
#   end

#   private

#   def ensure_user_bonid_and_qr_if_approved
#     return unless user.present?
#     user.generate_bonid! if user.bonid.blank?
#     update_column(:bonid, user.bonid) if bonid.blank?

#     # ✅ Citizen QR expires in 5 minutes, secure QR stays valid for 1 year
#     update_columns(
#       verified_at: (verified_at || Time.current),
#       expires_at: (expires_at || 5.minutes.from_now)
#     )

#     regenerate_combined_qr! if public_qr_png_base64.blank? || secure_qr_png_base64.blank?
#   end

#   def copy_user_photo_if_missing
#     return if selfie.attached?
#     return unless user&.photo&.attached?

#     selfie.attach(user.photo.blob)
#   end

#   def set_default_submission_type
#     self.submission_type ||= "initial"
#   end

#   def set_default_status
#     self.status ||= :pending
#   end

#   def generate_verification_token
#     self.verification_token ||= SecureRandom.hex(16)
#   end

#   def set_reset_requested_at
#     self.reset_requested_at ||= Time.current if reset_request_status_pending?
#   end

#   def set_staged_for_badbin
#     self.staged_for = :badbin if rejection_reason == "bad_bin"
#   end

#   def set_verified_fields_if_approved
#     return unless saved_change_to_status? && approved?
#     # ✅ When approved, set verified_at now + QR expiry 5 minutes for citizens
#     update_columns(
#       verified_at: Time.current,
#       expires_at: 5.minutes.from_now
#     ) unless verified_at.present? && expires_at.present?
#   end
# end
