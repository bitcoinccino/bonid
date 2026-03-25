class EmergencyContact < ApplicationRecord
  belongs_to :user

  # === Relations ===
  RELATIONS = [
    "Parent", "Spouse", "Sibling", "Child", "Relative",
    "Friend", "Neighbor", "Coworker", "Guardian", "Doctor", "Other"
  ].freeze

  VISIBILITY_LEVELS = {
    private: "Private",
    partners_only: "Visible to verified partners only",
    public: "Publicly visible"
  }.freeze

  VERIFICATION_STATUSES = {
    unverified: 0,
    pending: 1,
    verified: 2,
    failed: 3
  }.freeze

  # === Enums ===
  enum :visibility, VISIBILITY_LEVELS.keys, prefix: true, default: :private
   enum :verification_status, VERIFICATION_STATUSES, prefix: true, default: :unverified

  # === Validations ===
  validates :name, presence: true
  validates :relation, inclusion: { in: RELATIONS }, allow_blank: true
  validates :phone, format: { with: /\A\+?\d{6,15}\z/, message: "must be a valid phone number" }, allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  # BonID format: INITIALS-YEAR-SEX-DEPT-TYPE-ID-CHECKSUM (e.g., DV-1982-M-ARTIBONITE-P8697-761)
  validates :bonid, format: { with: /\A[A-Z]{2}-\d{4}-[MFU]-[A-Z]+-[A-Z]-\d+-[A-Z0-9]{3}\z/, message: "is not a valid BonID format" }, allow_blank: true

  # 🚫 Prevent self-BonID addition
  validate :cannot_add_own_bonid

  # === Callbacks ===
  before_validation :normalize_fields
  after_create :auto_sync_from_bonid, if: -> { bonid.present? }
  after_create :notify_bonid_contact, if: -> { bonid.present? }
  after_save :auto_mark_mutual_verification, if: -> { bonid.present? && saved_change_to_verification_status? }

  # === Scopes ===
  scope :verified, -> { where(verification_status: :verified) }
  scope :public_visible, -> { where(visibility: :public) }

  # === Instance Methods ===
  def verified?
    verification_status == "verified"
  end

  def public?
    visibility == "public"
  end

  # Get the linked BonID user (if contact was added via BonID)
  def bonid_user
    return nil if bonid.blank?
    @bonid_user ||= User.find_by(bonid: bonid)
  end

  # Get the photo of the BonID holder
  def bonid_photo
    bonid_user&.photo if bonid_user&.photo&.attached?
  end

  # === BonID Autofill ===
  def sync_from_bonid!
    bonid_user = User.find_by(bonid: bonid)
    return unless bonid_user&.identity_submissions&.approved&.last

    self.name    ||= bonid_user.full_name
    self.phone   ||= bonid_user.phone
    self.email   ||= bonid_user.email
    self.address ||= bonid_user.address&.full_address
    self.verification_status = :verified
    save!
  rescue => e
    Rails.logger.error "[EmergencyContact] BonID sync failed for #{bonid}: #{e.message}"
  end

  # === Mutual Verification Logic ===
  def mutual_verification?
    return false unless bonid.present?

    EmergencyContact
      .joins(:user)
      .where(bonid: user.bonid)
      .where(users: { bonid: bonid })
      .exists?
  end

  private

  # === Validation Rules ===
  def cannot_add_own_bonid
    return if bonid.blank? || user.blank?
    errors.add(:bonid, "cannot be your own BonID") if bonid == user.bonid
  end

  # === Normalization ===
  def normalize_fields
    self.name   = name.strip.titleize if name.present?
    # Normalize phone: keep only digits and optional leading +
    if phone.present?
      cleaned = phone.strip.gsub(/[^\d+]/, "")  # Remove everything except digits and +
      cleaned = cleaned.sub(/^\+/, "").prepend("+") if cleaned.start_with?("+")  # Ensure single +
      self.phone = cleaned.presence
    end
    self.email  = email.strip.downcase if email.present?
    self.bonid  = bonid.strip.upcase if bonid.present?
  end

  # === Sync Logic ===
  def auto_sync_from_bonid
    sync_from_bonid!
  end

  def auto_mark_mutual_verification
    return unless verified? && mutual_verification?

    reciprocal = EmergencyContact
      .joins(:user)
      .find_by(bonid: user.bonid, users: { bonid: bonid })

    reciprocal&.update(verification_status: :verified)
  end

  # === Notification to BonID Contact ===
  def notify_bonid_contact
    contact_user = User.find_by(bonid: bonid)
    return unless contact_user&.email.present?

    Citizens::CitizenMailer.with(
      contact_user: contact_user,
      added_by: user,
      relation: relation
    ).emergency_contact_added.deliver_later
  rescue => e
    Rails.logger.error "[EmergencyContact] Failed to notify BonID contact #{bonid}: #{e.message}"
  end
end
