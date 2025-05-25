class IdentitySubmission < ApplicationRecord
  require 'rqrcode'
  require 'base64'

  # === Associations
  belongs_to :user
  belongs_to :partner, optional: true
  has_many :qr_scans, dependent: :destroy
  has_many :qr_scan_logs, class_name: "QrScan", dependent: :destroy

  # === Attachments
  has_one_attached :cin_front
  has_one_attached :cin_back
  has_one_attached :passport
  has_one_attached :selfie
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
  has_one_attached :additional_proof

  # === Enums
  enum :status, { pending: 0, approved: 1, rejected: 2, revoked: 3 }
  enum :submission_type, { initial: "initial", resubmission: "resubmission", reissue: "reissue" }
  enum :reset_request_status, { pending: 0, approved: 1, rejected: 2 }, prefix: :reset_request_status
  enum :staged_for, { none: 0, bonbin: 1, badbin: 2 }, prefix: :staged_for

  # === Callbacks
  before_validation :set_default_submission_type, on: :create
  before_validation :set_default_status, on: :create
  before_create     :generate_verification_token
  before_save       :set_reset_requested_at, if: :reset_request_status_pending?
  before_save       :set_verified_at, if: -> { verified? || reset_request_status_approved? || reset_request_status_rejected? }
  before_save       :set_expires_at, if: -> { verified? }
  before_save       :set_staged_for_badbin, if: -> { staged_for_badbin? }
  after_update      :regenerate_combined_qr_if_approved

  # === Validations
  validates :id_type, presence: true, inclusion: { in: %w[cin passport] }
  validates :submission_type, presence: true, inclusion: { in: submission_types.keys }
  validates :reason, presence: true, if: -> { submission_type == "reissue" }
  validates :rejection_reason, presence: true, if: -> { staged_for_badbin? }
  validate :single_active_submission, on: :create
  validate :required_documents_present, unless: -> { skip_document_validations }

  # === Attributes
  attr_accessor :skip_document_validations

  # === Public Methods

  def verified?
    approved? && verified_at.present? && expires_at.present? && expires_at.future?
  end

  def mark_as_verified!
    update!(
      verified_at: Time.current,
      expires_at: 1.year.from_now,
      verification_token: SecureRandom.hex(40),
      status: :approved
    )
    regenerate_combined_qr!
  end

  def certificate_number
    "BONID-#{created_at.year}-#{id.to_s.rjust(5, '0')}"
  end

  def verification_qr_url
    Rails.application.routes.url_helpers.verify_identity_submission_url(
      verification_token,
      host: Rails.application.config.default_url_host
    )
  end

  def generate_qr_png_base64
    return qr_png_base64 if qr_png_base64.present?

    regenerate_combined_qr!
    qr_png_base64
  end

  def regenerate_combined_qr!
    raise "Missing verification token" if verification_token.blank?
    return unless user&.bonid.present?
  
    payload = {
      bonid: user.bonid,
      verification_token: verification_token,
      signature: user.send(:secure_bonid_signature),
      partner: partner&.slug # optional
    }
  
    qr = RQRCode::QRCode.new(payload.to_json)
  
    png = qr.as_png(
      bit_depth: 1,
      border_modules: 4,
      color_mode: :rgb,
      color: verified? ? '#00209F' : '#6B7280',
      fill: verified? ? '#FFFFFF' : '#D1D5DB',
      module_px_size: 6,
      size: 240
    )
  
    update_column(:qr_png_base64, Base64.strict_encode64(png.to_s))
  end
  

  def generate_secure_qr
    return unless user&.bonid.present?

    payload = "#{user.bonid}--#{user.send(:secure_bonid_signature)}"
    qr = RQRCode::QRCode.new(payload)
    png = qr.as_png(
      bit_depth: 1,
      border_modules: 4,
      color_mode: ChunkyPNG::COLOR_GRAYSCALE,
      color: 'black',
      fill: 'white',
      module_px_size: 6,
      size: 240
    )

    Base64.encode64(png.to_s)
  end

  def qr_svg
    return unless (base_url = ENV["NGROK_HOST"] || ENV["HOST_URL"])

    full_url = "#{base_url}/verify/#{verification_token}"
    RQRCode::QRCode.new(full_url).as_svg(
      offset: 0,
      color: "#000",
      shape_rendering: "crispEdges",
      module_size: 6,
      standalone: true
    )
  end

  def self.rejection_reasons_options
    {
      "ID Issues" => [
        ["Missing ID document: Upload a valid CIN (front and back) or Passport", "missing_id"],
        ["Blurry or unreadable ID photo", "blurry_id"],
        ["Expired ID document", "expired_id"],
        ["Non-Haitian ID submitted", "non_haitian_id"],
        ["Name mismatch on ID", "name_mismatch_id"],
        ["Suspected tampering with ID", "tampered_id"]
      ],
      "Selfie Issues" => [
        ["Missing selfie", "missing_selfie"],
        ["Blurry selfie", "blurry_selfie"],
        ["Selfie doesn’t match ID", "selfie_mismatch"],
        ["AI-altered selfie", "ai_altered_selfie"]
      ],
      "Proof of Address Issues" => [
        ["Missing proof of address", "missing_proof"],
        ["Invalid proof of address", "invalid_proof"],
        ["Outdated proof of address", "outdated_proof"]
      ],
      "Consistency Issues" => [
        ["Inconsistent information", "inconsistent_info"],
        ["Low-quality uploads", "low_quality_uploads"],
        ["Conflicting submissions", "conflicting_submissions"],
        ["Duplicate submission", "duplicate_submission"],
        ["Identity could not be verified", "unverified_identity"],
        ["Incomplete submission", "incomplete_submission"]
      ],
      "Other" => [["Other: Please specify below", "other"]]
    }
  end

  # === Validations

  def single_active_submission
    if user.identity_submissions.where(status: [:pending, :approved]).exists?
      errors.add(:base, "You already have a pending or approved submission.")
    end
  end

  def required_documents_present
    cin_complete = cin_front.attached? && cin_back.attached?
    passport_present = passport.attached?

    unless cin_complete || passport_present
      errors.add(:base, "You must upload both CIN Front and CIN Back OR a Passport.")
    end

    errors.add(:selfie, "must be attached.") unless selfie.attached?

    unless [
      digicel_phone_bill, natcom_phone_bill, baptismal_certificate, birth_certificate,
      adoption_certificate, naturalization_monitor_copy, archives_extract, pnh_record,
      bank_record, western_union_record, moneygram_record, sendwave_record,
      unitransfer_record, taptap_record, additional_proof
    ].any?(&:attached?)
      errors.add(:base, "You must upload at least one supporting document.")
    end
  end

  # === Callbacks

  def regenerate_combined_qr_if_approved
    return unless saved_change_to_status? && approved?
    regenerate_combined_qr!
  end

  # === Private
  private

  def generate_verification_token
    self.verification_token ||= SecureRandom.hex(16)
  end

  def set_default_submission_type
    self.submission_type ||= "initial"
  end

  def set_default_status
    self.status ||= :pending
  end

  def set_reset_requested_at
    self.reset_requested_at ||= Time.current if reset_request_status_pending?
  end

  def set_staged_for_badbin
    self.staged_for = :badbin if rejection_reason == "bad_bin"
  end

  def set_verified_at
    self.verified_at ||= Time.current if approved?
  end

  def set_expires_at
    self.expires_at ||= 1.year.from_now if approved?
  end
end





















# class IdentitySubmission < ApplicationRecord
#   require 'rqrcode'
#   require 'base64'

#   # === Associations
#   belongs_to :user
#   belongs_to :partner, optional: true
#   has_many :qr_scans, dependent: :destroy
#   has_many :qr_scan_logs, class_name: "QrScan", dependent: :destroy

#   # === Attachments
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

#   # === Enums
#   enum :status, { pending: 0, approved: 1, rejected: 2, revoked: 3 }
#   enum :submission_type, { initial: "initial", resubmission: "resubmission", reissue: "reissue" }
#   enum :reset_request_status, { pending: 0, approved: 1, rejected: 2 }, prefix: :reset_request_status
#   enum :staged_for, { none: 0, bonbin: 1, badbin: 2 }, prefix: :staged_for

#   # === Callbacks
#   before_validation :set_default_submission_type, on: :create
#   before_validation :set_default_status, on: :create
#   before_create     :generate_verification_token
#   before_save       :set_reset_requested_at, if: :reset_request_status_pending?
#   before_save       :set_verified_at, if: -> { verified? || reset_request_status_approved? || reset_request_status_rejected? }
#   before_save       :set_expires_at, if: -> { verified? }
#   before_save       :set_staged_for_badbin, if: -> { staged_for_badbin? }
#   after_create      :regenerate_qr!
#   after_update      :regenerate_secure_qr_if_approved

#   # === Validations
#   validates :id_type, presence: true, inclusion: { in: %w[cin passport] }
#   validates :submission_type, presence: true, inclusion: { in: submission_types.keys }
#   validates :reason, presence: true, if: -> { submission_type == "reissue" }
#   validates :rejection_reason, presence: true, if: -> { staged_for_badbin? }
#   validate :single_active_submission, on: :create
#   validate :required_documents_present, unless: -> { skip_document_validations }

#   # === Attributes
#   attr_accessor :skip_document_validations

#   # === Methods

#   def verified?
#     approved? && verified_at.present? && expires_at.present? && expires_at.future?
#   end

#   def mark_as_verified!
#     update!(
#       verified_at: Time.current,
#       expires_at: 1.year.from_now,
#       verification_token: SecureRandom.hex(40),
#       status: :approved
#     )
#   end

#   def certificate_number
#     "BONID-#{created_at.year}-#{id.to_s.rjust(5, '0')}"
#   end

#   def verification_qr_url
#     Rails.application.routes.url_helpers.verify_identity_submission_url(
#       verification_token,
#       host: Rails.application.config.default_url_host
#     )
#   end

#   def generate_qr_png_base64
#     return qr_png_base64 if qr_png_base64.present?

#     regenerate_qr!
#     qr_png_base64
#   end

#   def regenerate_combined_qr!
#     raise "Missing verification token" if verification_token.blank?

#     payload = {
#       bonid: user.bonid,
#       signature: user.send(:secure_bonid_signature),
#       verification_token: verification_token,
#       partner: partner&.slug
#     }

#     qr = RQRCode::QRCode.new(payload.to_json)
#     png = qr.as_png(
#       bit_depth: 1,
#       border_modules: 4,
#       color_mode: :rgb,
#       color: verified? ? '#00209F' : '#6B7280',
#       fill: verified? ? '#FFFFFF' : '#D1D5DB',
#       module_px_size: 6,
#       size: 240
#     )

#     update_column(:qr_png_base64, Base64.strict_encode64(png.to_s))
#   end

#   def generate_secure_qr
#     return unless user&.bonid.present?

#     payload = "#{user.bonid}--#{user.send(:secure_bonid_signature)}"
#     qr = RQRCode::QRCode.new(payload)
#     png = qr.as_png(
#       bit_depth: 1,
#       border_modules: 4,
#       color_mode: ChunkyPNG::COLOR_GRAYSCALE,
#       color: 'black',
#       fill: 'white',
#       module_px_size: 6,
#       size: 240
#     )

#     Base64.encode64(png.to_s)
#   end

#   def qr_svg
#     return unless (base_url = ENV["NGROK_HOST"] || ENV["HOST_URL"])

#     full_url = "#{base_url}/verify/#{verification_token}"
#     RQRCode::QRCode.new(full_url).as_svg(
#       offset: 0,
#       color: "#000",
#       shape_rendering: "crispEdges",
#       module_size: 6,
#       standalone: true
#     )
#   end

#   def self.rejection_reasons_options
#     {
#       "ID Issues" => [
#         ["Missing ID document: Upload a valid CIN (front and back) or Passport", "missing_id"],
#         ["Blurry or unreadable ID photo", "blurry_id"],
#         ["Expired ID document", "expired_id"],
#         ["Non-Haitian ID submitted", "non_haitian_id"],
#         ["Name mismatch on ID", "name_mismatch_id"],
#         ["Suspected tampering with ID", "tampered_id"]
#       ],
#       "Selfie Issues" => [
#         ["Missing selfie", "missing_selfie"],
#         ["Blurry selfie", "blurry_selfie"],
#         ["Selfie doesn’t match ID", "selfie_mismatch"],
#         ["AI-altered selfie", "ai_altered_selfie"]
#       ],
#       "Proof of Address Issues" => [
#         ["Missing proof of address", "missing_proof"],
#         ["Invalid proof of address", "invalid_proof"],
#         ["Outdated proof of address", "outdated_proof"]
#       ],
#       "Consistency Issues" => [
#         ["Inconsistent information", "inconsistent_info"],
#         ["Low-quality uploads", "low_quality_uploads"],
#         ["Conflicting submissions", "conflicting_submissions"],
#         ["Duplicate submission", "duplicate_submission"],
#         ["Identity could not be verified", "unverified_identity"],
#         ["Incomplete submission", "incomplete_submission"]
#       ],
#       "Other" => [["Other: Please specify below", "other"]]
#     }
#   end

#   # === Custom Validations

#   def single_active_submission
#     if user.identity_submissions.where(status: [:pending, :approved]).exists?
#       errors.add(:base, "You already have a pending or approved submission.")
#     end
#   end

#   def required_documents_present
#     cin_complete = cin_front.attached? && cin_back.attached?
#     passport_present = passport.attached?

#     unless cin_complete || passport_present
#       errors.add(:base, "You must upload both CIN Front and CIN Back OR a Passport.")
#     end

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

#   # === Private Methods
#   private

#   def generate_verification_token
#     self.verification_token ||= SecureRandom.hex(16)
#   end

#   def set_default_submission_type
#     self.submission_type ||= "initial"
#   end

#   def set_default_status
#     self.status ||= :pending
#   end

#   def set_reset_requested_at
#     self.reset_requested_at ||= Time.current if reset_request_status_pending?
#   end

#   def set_staged_for_badbin
#     self.staged_for = :badbin if rejection_reason == "bad_bin"
#   end

#   def regenerate_secure_qr_if_approved
#     return unless saved_change_to_status? && approved?
#     user.regenerate_combined_qr! if user.present?
#   end
# end


