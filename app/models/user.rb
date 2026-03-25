# == Schema Information
#
# Table name: users
#
# BonID unified User model — shared by citizens, officers, partner admins, reviewers, and admins.
# Uses Devise for authentication and Rolify for role management.
#
# Each user can hold multiple roles (citizen, officer, partner_admin, reviewer, admin_user, etc.)
#

require "openssl"

class User < ApplicationRecord
  include BonidGenerator
  self.store_full_sti_class = false

  # === Rolify Setup ===
  rolify

  # === Includes ===
  include DocumentIssuers

  # === Devise Modules ===
  devise :invitable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, :timeoutable

  # === Active Storage Attachments ===
  has_one_attached :photo
  has_one_attached :id_document_front
  has_one_attached :id_document_back

  # === Core Polymorphic Associations ===
  has_one :address, as: :addressable, inverse_of: :addressable, dependent: :destroy
  accepts_nested_attributes_for :address, allow_destroy: true

  # === Extended Associations ===
  has_one :citizen_profile, dependent: :destroy
  has_one  :physical_profile, dependent: :destroy
  has_one  :health_profile,   dependent: :destroy
  has_one  :officer,          dependent: :destroy
  has_many :citizen_sessions, dependent: :destroy
  has_many :identity_submissions, dependent: :destroy
  has_many :name_change_requests, dependent: :destroy
  has_many :managed_partners, class_name: "Partner", foreign_key: :admin_user_id
  has_many :person_involvements, dependent: :nullify
  has_many :emergency_contacts, dependent: :destroy
  has_many :social_handles,     dependent: :destroy
  has_many :family_members,     dependent: :destroy
  has_many :family_links,       class_name: "FamilyMember", foreign_key: :linked_user_id
  has_many :verification_records, dependent: :destroy
  has_many :consent_grants,    foreign_key: :citizen_id, dependent: :destroy
  has_many :transaction_consents, foreign_key: :citizen_id, dependent: :destroy
  has_many :bonid_aliases, dependent: :destroy

  # === (DEPRECATED — remove later after DB migration)
  has_many :bank_profiles, class_name: "BankProfile", dependent: :nullify

  # === Partner Relations ===
  belongs_to :partner,        optional: true
  belongs_to :partner_branch, optional: true

  # === Birth Metadata ===
  belongs_to :birth_department, class_name: "Department", optional: true
  belongs_to :birth_commune,    class_name: "Commune",    optional: true

  # === Virtual Attributes ===
  attr_accessor :skip_password, :terms

  # === Nested Attributes ===
  # Note: Rails params use string keys, so we check both symbol and string keys
  accepts_nested_attributes_for :emergency_contacts,
                                allow_destroy: true,
                                reject_if: ->(attrs) {
                                  (attrs["name"] || attrs[:name]).blank?
                                }
  accepts_nested_attributes_for :social_handles,
                                allow_destroy: true,
                                reject_if: ->(attrs) {
                                  (attrs["platform"] || attrs[:platform]).blank? ||
                                  (attrs["handle"] || attrs[:handle]).blank?
                                }
  accepts_nested_attributes_for :health_profile,     update_only: true
  accepts_nested_attributes_for :physical_profile,   update_only: true
  accepts_nested_attributes_for :bank_profiles,
                                allow_destroy: true,
                                reject_if: ->(attrs) {
                                  # Reject if all meaningful values are blank
                                  attrs.except("id", "_destroy", :id, :_destroy).values.all?(&:blank?)
                                }
  accepts_nested_attributes_for :family_members,
                                allow_destroy: true,
                                reject_if: ->(attrs) {
                                  (attrs["first_name"] || attrs[:first_name]).blank? ||
                                  (attrs["last_name"] || attrs[:last_name]).blank?
                                }

  # === Callbacks ===
  after_create :assign_default_citizen_role, if: -> { roles.blank? }
  after_invitation_accepted :ensure_officer_role, if: :officer_invitation?
  after_invitation_accepted :create_officer_if_needed
  after_update :sync_name_to_officer, if: :name_fields_changed?

  # === Validations ===
  with_options unless: :admin? do
    validates :terms, acceptance: { accept: "1" }, on: :create
    validates :id_number, presence: true, if: -> { id_type.present? }
    validates :id_type,   presence: true, if: -> { id_number.present? }
  end

  validates :partner, presence: true, if: :partner_admin?
  validate  :branch_belongs_to_partner, if: -> { partner_branch.present? && partner.present? }

  # === Enums ===
  enum :sex, { male: 0, female: 1, other: 2 }
  enum :marital_status, { single: 0, married: 1, divorced: 2, widowed: 3 }
  enum :id_type, { cin: 0, passport: 1, driver_license: 2, national_card: 3, nif: 4 }

# === Name Prefix & Suffix Options ===========================================
PREFIXES = [
  "Mr",
  "Ms",
  "Mrs",
  "Miss",
  "Dr"
]

SUFFIXES = [
  "Jr",
  "Sr",
  "II",
  "III",
  "IV",
  "V"
]


  # === Scopes ===
  scope :with_role, ->(role_name) { joins(:roles).where(roles: { name: role_name }) }

  # === Age Calculation ===
  def age
    return unless dob
    now = Date.current
    age = now.year - dob.year
    age -= 1 if now < dob + age.years
    age
  end

  # === Address Helpers ===
  def address
    super || partner_branch&.address
  end

  def formatted_address
    return unless address.present?
    [
      address.street_address,
      address.locality,
      address.postal_code,
      address.commune&.name&.upcase,
      address.department&.name&.upcase,
      address.country&.upcase || "HAITI"
    ].compact_blank.join(", ")
  end
  alias full_address formatted_address

  # === BonID Profile Snapshot ===
  def bonid_profile
    submission = identity_submissions.order(verified_at: :desc).first
    url = Rails.application.routes.url_helpers

    {
      bonid: bonid || submission&.bonid,
      verification_status: submission&.status,
      verified_at: submission&.verified_at&.iso8601,
      expires_at: submission&.expires_at&.iso8601,
      id_type: id_type || submission&.id_type,
      issuing_authority: issuing_authority || "Office National d’Identification (ONI)",
      first_name: first_name,
      middle_name: middle_name,
      last_name: last_name,
      dob: dob,
      sex: sex,
      marital_status: marital_status,
      nationality: nationality,
      phone: phone,
      email: email,
      address: formatted_address,
      birth_department_id: birth_department_id,
      birth_commune_id: birth_commune_id,
      place_of_birth: place_of_birth,
      qr_verify_url: "https://bonid.ht/verify/#{bonid}",
      qr_png_base64: submission&.public_qr_png_base64,
      photo_url: (url.url_for(photo) if photo&.attached?),
      id_document_front_url: (url.url_for(id_document_front) if id_document_front&.attached?),
      id_document_back_url: (url.url_for(id_document_back) if id_document_back&.attached?),
      document_issuer: document_issuer
    }.compact
  end

  # === STI-safe Address Builder ===
  def build_address_with_defaults(attrs = {})
    addr = address || build_address(attrs)
    addr.country ||= "Haiti"
    addr.sync_inverse_addressable if addr.respond_to?(:sync_inverse_addressable)
    addr
  end

  # === Role & Partner Validation ===
  def branch_belongs_to_partner
    return if partner_branch.partner_id == partner_id
    errors.add(:partner_branch, "must belong to the same partner organization")
  end

  # === Devise Scope Mapping (CLEAN) ===
  def devise_scope
    if partner_admin?
      :partner_admin
    elsif officer?
      :officer
    elsif reviewer?
      :reviewer
    elsif has_role?(:admin_user)
      :admin_user
    else
      :citizen
    end
  end

  # === Role Helpers ===
  # Cached role check — avoids SQL query on every request (called by require_citizen!).
  # 15-minute TTL; invalidated on add_role/remove_role.
  def has_role?(name)
    Rails.cache.fetch("user_roles:#{id}:#{name}", expires_in: 15.minutes) do
      roles.exists?(name: name)
    end
  end

  def clear_role_cache!
    %w[citizen officer partner_admin reviewer admin admin_user].each do |role|
      Rails.cache.delete("user_roles:#{id}:#{role}")
    end
  end

  def add_role(name, resource = nil)
    clear_role_cache!
    super
  end

  def remove_role(name, resource = nil)
    clear_role_cache!
    super
  end

  def citizen?       = has_role?(:citizen)
  def officer?       = has_role?(:officer)
  def partner_admin? = has_role?(:partner_admin)
  def reviewer?      = has_role?(:reviewer)
  def admin?         = has_role?(:admin)

  # === Display Helpers ===
  def full_name = [ first_name, middle_name, last_name ].compact_blank.join(" ").presence || email
  def branch_name    = partner_branch&.name || "—"
  def branch_address = partner_branch&.address&.full_formatted || "—"

# === FULL NAME HELPERS =======================================================

def formatted_prefix
  return nil if prefix.blank?
  prefix.to_s.titleize  # "mr" → "Mr"
end

def formatted_suffix
  return nil if suffix.blank?
  suffix.to_s.upcase    # "jr" → "JR"
end

def formatted_base_name
  [
    first_name&.strip&.titleize,
    middle_name&.strip&.titleize,
    last_name&.strip&.titleize
  ].compact.join(" ")
end

def full_name
  [
    formatted_prefix,
    formatted_base_name,
    formatted_suffix
  ].compact.join(" ").presence || email
end

alias display_name full_name
alias name full_name


  # === QR Signature Helpers ===

  # DEPRECATED: Legacy HMAC — kept for backward compat during v1→v2 migration.
  def secure_bonid_signature
    key = Rails.application.credentials.dig(:bonid, :signature_secret) ||
          raise("Missing bonid:signature_secret")
    OpenSSL::HMAC.hexdigest("SHA256", key, bonid.to_s)
  end

  def verify_bonid_signature(signature)
    return false unless signature.is_a?(String) &&
                        signature.length == secure_bonid_signature.length
    ActiveSupport::SecurityUtils.secure_compare(signature, secure_bonid_signature)
  end

  def generate_qr_payload
    submission = verified_identity_submission
    exp = submission&.expires_at || 5.years.from_now

    BonidQrSigner.sign(bonid: bonid, expires_at: exp).to_json
  end

  # DEPRECATED: Legacy HMAC — kept for backward compat during v1→v2 migration.
  def qr_signature(timestamp)
    key = Rails.application.credentials.dig(:bonid, :signature_secret)
    data = "#{bonid}#{timestamp}"
    OpenSSL::HMAC.hexdigest("SHA256", key, data)
  end

  def verify_qr_payload(payload)
    # --- Ed25519 v2 payload ---
    if payload.is_a?(Hash) && payload["v"].to_i == 2 && payload["sig"].present?
      result = BonidQrSigner.verify(payload)
      return result == :valid
    end

    # --- Legacy HMAC fallback (v1 / unversioned) ---
    return false unless payload.is_a?(Hash) && payload["bonid"] == bonid
    ts  = payload["timestamp"].to_i
    sig = payload["signature"]
    return false if Time.now.to_i - ts > 900
    ActiveSupport::SecurityUtils.secure_compare(sig, qr_signature(ts))
  end

  def verify_submission_signature(submission)
    secret = Rails.application.credentials.dig(:bonid, :signature_secret)
    return false unless secret.present?
    return false unless submission.present? && submission.hmac_signature_value.present?

    payload_for_hmac = {
      bonid: bonid,
      timestamp: submission.verified_at.to_i.to_s
    }

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, payload_for_hmac.to_json)

    ActiveSupport::SecurityUtils.secure_compare(submission.hmac_signature_value, expected)
  end

  # === BonID Generation (with checksum) ===
  def generate_bonid!
    initials   = [ first_name&.first, last_name&.first ].compact.join.upcase.presence || "XX"
    year       = dob.present? ? dob.year.to_s : Time.current.year.to_s
    sex_code   = (sex.presence || "U").to_s[0].upcase
    id_suffix  = id_number.to_s.gsub(/\D/, "")[-4..] || "0000"

    # Location code: ISO country code for diaspora, department code for domestic
    latest_submission = identity_submissions.order(created_at: :desc).first
    residence_country = latest_submission&.country_of_residence

    if residence_country.present? && residence_country != "HT"
      # Diaspora: use ISO country code (US, DO, CA, FR, CL, BR, etc.)
      location_code = residence_country.upcase
    else
      # Domestic: use Haitian department abbreviation
      dept_name = address&.department&.name&.upcase || "HAITI"
      location_code = department_abbreviation(dept_name)
    end

    base_code  = "#{initials}-#{year}-#{sex_code}-#{location_code}-P#{id_suffix}"

    secret     = Rails.application.credentials.dig(:bonid, :signature_secret)
    digest     = OpenSSL::HMAC.hexdigest("SHA256", secret, base_code)
    checksum   = digest[0..2].upcase

    bonid_code = "#{base_code}-#{checksum}"

    counter = 1
    while User.exists?(bonid: bonid_code)
      bonid_code = "#{base_code}-#{checksum}-#{counter}"
      counter += 1
    end

    update!(bonid: bonid_code)
    Rails.logger.info("✅ BonID generated for User##{id}: #{bonid_code}")
    bonid_code
  rescue => e
    Rails.logger.error("❌ Failed to generate BonID for User##{id}: #{e.message}")
    nil
  end

  def bonid_verified?
    identity_submissions.approved.exists?
  end

  # === Misc ===
  def password_required?
    !skip_password && super
  end

  def verified_identity_submission
    identity_submissions.find_by(status: :approved)
  end

  def profile_complete?
    return false unless citizen?
    required = [
      first_name, last_name, dob, sex, phone, id_type, id_number,
      address&.street_address, address&.country
    ]
    required.all?(&:present?) && photo.attached?
  end

  def profile_completion_percentage
    total = 5.0
    score = 0
    score += 1 if first_name.present? && last_name.present? && dob.present?
    score += 1 if physical_profile.present?
    score += 1 if health_profile.present?
    score += 1 if bank_profiles.any?
    score += 1 if emergency_contacts.any?
    ((score / total) * 100).round
  end

  # === Default Roles ===
  private

  def assign_default_citizen_role
    add_role(:citizen)
  end

  def officer_invitation?
    partner&.sector == "law_enforcement"
  end

  def ensure_officer_role
    add_role(:officer) unless has_role?(:officer)
  end

  def create_officer_if_needed
    return unless officer? && officer.blank?
    allowed_slugs = %w[pnh police-nationale-dhaiti]
    return unless partner&.sector == "law_enforcement" &&
                  allowed_slugs.include?(partner&.slug)

    build_officer(
      email: email,
      partner_id: identity_submissions.approved&.last&.partner_id || partner_id,
      badge_id: "PNH#{SecureRandom.hex(4).upcase}",
      first_name: first_name || "Unknown",
      last_name: last_name || "Unknown",
      unit_name: OfficerConstants::UNIT_OPTIONS.keys.first,
      unit_type: OfficerConstants::UNIT_OPTIONS.values.flatten.first,
      rank: "Officer",
      password: SecureRandom.hex(12)
    ).save(validate: false)
  end

  def devise_mailer
    ::UserMailer
  end

  # === Name Sync: keep officer record in step with citizen name ===
  # When a User who is also an Officer updates their name via the citizen portal,
  # propagate the change to the officers table so both portals show the same name.
  # Uses update_columns to skip officer validations (rank, badge_id, etc.).
  def name_fields_changed?
    first_name_previously_changed? ||
      last_name_previously_changed? ||
      middle_name_previously_changed?
  end

  def sync_name_to_officer
    return unless officer.present?

    officer.update_columns(
      first_name:  first_name,
      last_name:   last_name,
      middle_name: middle_name
    )
  end
end


# require "openssl" # required for HMAC SHA256 QR signature

# class User < ApplicationRecord
#   # === Devise ===
#   devise :invitable, :database_authenticatable, :registerable,
#          :recoverable, :rememberable, :validatable

#   # === Associations ===
#   has_one :officer
#   has_one :address, as: :addressable, dependent: :destroy
#   has_many :identity_submissions, dependent: :destroy
#   accepts_nested_attributes_for :address
#   has_many :managed_partners, class_name: "Partner", foreign_key: :admin_user_id

#   # === Virtual Attributes ===
#   attr_accessor :terms

#   # === Validations ===
#   validates :terms, acceptance: { accept: '1' }, on: :create

#   # === Enums ===
#   enum role_int: {
#     user: 0,
#     admin: 1,
#     partner_admin: 2,
#     reviewer: 3
#   }

#   enum sex: {
#     M: 0,
#     F: 1
#   }

#   enum marital_status: {
#     married: 0,
#     divorced: 1,
#     widowed: 2,
#     single: 3,
#     separated: 4,
#     engaged: 5
#   }

#   enum id_type: {
#     cin: 0,
#     passport: 1
#   }

#   # === Scopes ===
#   scope :admins,    -> { where(role_int: :admin) }
#   scope :reviewers, -> { where(role_int: :reviewer) }
#   scope :partners,  -> { where(role_int: :partner_admin) }

#   # === Role Check Methods ===
#   def admin?    = role_int == "admin"
#   def reviewer? = role_int == "reviewer"
#   def partner?  = role_int == "partner_admin"
#   def officer?  = officer.present?

#   # === Identity Submission Helpers ===

#   # Returns the approved identity submission, or nil if none
#   def approved_identity_submission
#     identity_submissions.find_by(status: "approved")
#   end

#   # Returns true if user has at least one approved identity submission
#   def has_verified_bonid?
#     approved_identity_submission.present?
#   end

#   # === Display ===
#   def full_name
#     [first_name, middle_name, last_name].compact.join(" ")
#   end

#   # === BONID ===

#   # Unique BONID saved to DB (real ID)
#   def generate_bonid!
#     prefix = "#{last_name.to_s[0..1].upcase}-#{dob&.year}-#{sex.to_s[0].upcase rescue 'U'}-#{address&.commune&.department&.name&.upcase || 'HT'}-C"
#     loop do
#       code = "#{prefix}-#{rand(1000..9999)}"
#       break code unless User.exists?(bonid: code)
#     end
#   end

#   # Fallback BONID for display (not persisted)
#   def generate_fallback_bonid
#     ln        = last_name.to_s[0..1].upcase.presence || "XX"
#     year      = dob&.year.to_s || "XXXX"
#     gender    = sex.to_s[0].upcase rescue "U"
#     dept      = address&.commune&.department&.name&.upcase&.delete(" ") || "UNKNOWN"
#     id_prefix = id_type.to_s[0].upcase rescue "U"
#     last4     = id_number.to_s[-4..] || "0000"

#     "#{ln}-#{year}-#{gender}-#{dept}-#{id_prefix}-#{last4}"
#   end

#   # Always return a BONID, even if not saved yet
#   def bonid
#     read_attribute(:bonid) || generate_fallback_bonid
#   end

#   # === QR Signature Logic ===

#   # Generate a static HMAC signature based on bonid only
#   def secure_bonid_signature
#     key = Rails.application.credentials.dig(:bonid, :signature_secret)
#     OpenSSL::HMAC.hexdigest("SHA256", key, bonid.to_s)
#   end

#   def verify_bonid_signature(signature)
#     ActiveSupport::SecurityUtils.secure_compare(signature, secure_bonid_signature)
#   end

#   # Generate QR payload that includes timestamped signature
#   def generate_qr_payload
#     ts = Time.now.to_i
#     {
#       bonid: bonid,
#       timestamp: ts,
#       signature: qr_signature(ts)
#     }.to_json
#   end

#   # HMAC signature based on bonid + timestamp
#   def qr_signature(timestamp)
#     key = Rails.application.credentials.dig(:bonid, :signature_secret)
#     data = "#{bonid}#{timestamp}"
#     OpenSSL::HMAC.hexdigest("SHA256", key, data)
#   end

#   # Verifies the timestamped QR payload is valid and fresh (<= 2 min old)
#   def verify_qr_payload(payload)
#     bonid = payload["bonid"]
#     ts    = payload["timestamp"].to_i
#     sig   = payload["signature"]

#     return false if Time.now.to_i - ts > 120 # Reject expired payloads

#     expected_sig = qr_signature(ts)
#     ActiveSupport::SecurityUtils.secure_compare(sig, expected_sig)
#   end

#   private

#    def find_district_from_postal_code
#      pc = address&.postal_code
#      return "UNKNOWN" if pc.blank?

#      case pc[2].to_i
#      when 1 then "NORD"
#      when 2 then "NORD-EST"
#      when 3 then "NORD-OUEST"
#      when 4 then "CENTRE"
#      when 5 then "ARTIBONITE"
#     when 6 then "OUEST"
#      when 7 then "SUD-EST"
#      when 8 then "SUD"
#     when 9 then "GRAND'ANSE"
#     else "UNKNOWN"
#     end
#  end
# end
