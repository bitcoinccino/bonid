# frozen_string_literal: true

class Officer < ApplicationRecord
  include BonidGenerator
  include OfficerConstants
  include OfficerAccessControl

  devise :invitable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable, authentication_keys: [ :email ]

  def devise_mailer
    Officers::OfficerMailer
  end


  belongs_to :user, optional: true
  delegate :first_name, :last_name, :middle_name, to: :user, prefix: :identity, allow_nil: true
  # Associations
  belongs_to :partner
  has_one :address, as: :addressable, dependent: :destroy
  accepts_nested_attributes_for :address
  belongs_to :user, optional: true

  has_many :identity_submissions, through: :user
  has_many :incident_reports, dependent: :destroy
  has_many :scan_logs, class_name: "QrScanLog", dependent: :nullify
  has_many :failed_bonid_lookups, dependent: :destroy
  has_many :qr_scans, dependent: :destroy
  has_many :qr_scan_logs, dependent: :destroy
  has_many :border_entries, dependent: :nullify

  has_one_attached :photo

  # Enums
  enum :status, { invited: 0, active: 1, revoked: 2 }, default: :invited

  enum :role, {
    officer: 0,
    director_general: 1,
    inspector_general: 2,
    agent: 3,
    admin: 4
  }, default: :officer

  # Constants
  VALID_UNIT_TYPES = OfficerConstants::UNIT_OPTIONS.values.flatten.freeze

  # VALIDATIONS
  with_options unless: :updating_password? do
    validates :partner_id, presence: true
    validates :unit_name, presence: true, inclusion: { in: OfficerConstants::UNIT_OPTIONS.keys }
    validates :unit_type, presence: true, inclusion: { in: VALID_UNIT_TYPES }
    validates :badge_id, presence: true, uniqueness: true, format: { with: /\A[A-Z0-9\-]+\z/ }
    validates :first_name, :last_name, :role, :rank, presence: true
    validates :email, presence: true, uniqueness: true
    validates :approved, inclusion: { in: [ true ] }, on: :scan
    validates :department_directorate,
      inclusion: { in: OfficerConstants::DEPARTMENTS.keys },
      allow_blank: true
  end

  # Scopes — status
  scope :active,   -> { where(status: :active) }
  scope :invited,  -> { where(status: :invited) }
  scope :revoked,  -> { where(status: :revoked) }
  scope :approved, -> { where(approved: true) }

  # Scopes — unit & rank (used by access control and partner portal)
  scope :in_unit, ->(unit) { where(unit_name: unit) }
  scope :field_rank,      -> { where(rank: OfficerConstants::RANK_GROUPS.select { |_, v| v == :field }.keys) }
  scope :supervisor_rank, -> { where(rank: OfficerConstants::RANK_GROUPS.select { |_, v| v == :supervisor }.keys) }
  scope :strategic_rank,  -> { where(rank: OfficerConstants::RANK_GROUPS.select { |_, v| v == :strategic }.keys) }

  # Convenience methods
  def full_name
    # Prioritize identity name, fallback to officer table name
    fname = identity_first_name || first_name
    lname = identity_last_name || last_name
    mname = identity_middle_name || middle_name

    [ fname, mname&.first, lname ].compact.join(" ")
  end

  def senior_officer?
    director_general? || inspector_general?
  end

  def command_level?
    senior_officer? || admin?
  end

  def staff?
    agent? || officer?
  end

  def admin?
    role == "admin"
  end

  # Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[
      id first_name last_name middle_name badge_id department_id
      unit_type unit_name email phone_number status rank role sector
      approved approved_at created_at updated_at department_directorate
    ]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[department partner]
  end

  private

  def updating_password?
    password.present? || password_confirmation.present?
  end
end
# class Officer < ApplicationRecord
#   include BonidGenerator
#   include OfficerConstants

#   devise :invitable, :database_authenticatable, :registerable,
#          :recoverable, :rememberable, :validatable,
#          :trackable, authentication_keys: [ :email ]

#   # 👇 force OfficerMailer for officers
#   def devise_mailer
#     Officers::OfficerMailer
#   end

#   belongs_to :partner
#   has_one :address, as: :addressable, dependent: :destroy
#   accepts_nested_attributes_for :address
#   belongs_to :user, optional: true

#   has_many :identity_submissions, through: :user
#   has_many :incident_reports, dependent: :destroy
#   has_many :scan_logs, class_name: "QrScanLog", dependent: :nullify
#   has_many :failed_bonid_lookups, dependent: :destroy
#   has_many :qr_scans, dependent: :destroy
#   has_many :qr_scan_logs, dependent: :destroy
#   has_many :border_entries, dependent: :nullify


#   has_one_attached :photo

#   enum :status, { invited: 0, active: 1, revoked: 2 }, default: :invited

#   enum :role, {
#     officer: 0,
#     director_general: 1,
#     inspector_general: 2,
#     agent: 3,
#     admin: 4
#   }, default: :officer

#   VALID_UNIT_TYPES = OfficerConstants::UNIT_OPTIONS.values.flatten.freeze

#   def self.unit_options
#     OfficerConstants::UNIT_OPTIONS
#   end

#   # Validations
#   with_options unless: :updating_password? do
#     validates :partner_id, presence: true
#     validates :unit_name, presence: true, inclusion: { in: OfficerConstants::UNIT_OPTIONS.keys }
#     validates :unit_type, presence: true, inclusion: { in: VALID_UNIT_TYPES }
#     validates :badge_id, presence: true, uniqueness: true, format: { with: /\A[A-Z0-9\-]+\z/ }
#     validates :first_name, :last_name, :role, :rank, presence: true
#     validates :email, presence: true, uniqueness: true
#     validates :approved, inclusion: { in: [ true ] }, on: :scan
#   end

#   # Scopes
#   scope :active,   -> { where(status: :active) }
#   scope :invited,  -> { where(status: :invited) }
#   scope :revoked,  -> { where(status: :revoked) }
#   scope :approved, -> { where(approved: true) }

#   # Convenience methods
#   def full_name
#     [ first_name, middle_name&.first, last_name ].compact.join(" ")
#   end

#   # ✅ Clean role helpers
#   def senior_officer?
#     director_general? || inspector_general?
#   end

#   def command_level?
#     senior_officer? || admin?
#   end

#   def staff?
#     agent? || officer?
#   end

#   def admin?
#     role == "admin"
#   end

#   # Ransack configuration
#   def self.ransackable_attributes(_auth_object = nil)
#     %w[
#       id first_name last_name middle_name badge_id department_id
#       unit_type unit_name email phone_number status rank role
#       approved approved_at created_at updated_at
#     ]
#   end

#   def self.ransackable_associations(_auth_object = nil)
#     %w[department partner]
#   end

#   private

#   def updating_password?
#     password.present? || password_confirmation.present?
#   end
# end

# class Officer < ApplicationRecord
#   include OfficerConstants

#   devise :database_authenticatable, :registerable,
#          :recoverable, :rememberable, :validatable,
#          :trackable, authentication_keys: [:email]

#   belongs_to :partner
#   has_one :address, as: :addressable, dependent: :destroy
#   accepts_nested_attributes_for :address
#   belongs_to :user, optional: true
#   has_many :identity_submissions, through: :user
#   has_many :incident_reports, dependent: :destroy
#   has_many :scan_logs, class_name: "QrScanLog", dependent: :nullify
#   has_many :failed_bonid_lookups, dependent: :destroy
#   has_many :qr_scans, dependent: :destroy
#   has_many :qr_scan_logs, dependent: :destroy

#   has_one_attached :photo

#   enum status: { invited: 0, active: 1, revoked: 2 }, default: :invited

#   enum role: {
#     officer: 0,
#     director_general: 1,
#     inspector_general: 2,
#     agent: 3,
#     admin: 4
#   }, default: :officer

#   VALID_UNIT_TYPES = OfficerConstants::UNIT_OPTIONS.values.flatten.freeze

#   def self.unit_options
#     OfficerConstants::UNIT_OPTIONS
#   end

#   # Validations
#   with_options unless: :updating_password? do
#     validates :partner_id, presence: true
#     validates :unit_name, presence: true, inclusion: { in: OfficerConstants::UNIT_OPTIONS.keys }
#     validates :unit_type, presence: true, inclusion: { in: VALID_UNIT_TYPES }
#     validates :badge_id, presence: true, uniqueness: true, format: { with: /\A[A-Z0-9\-]+\z/ }
#     validates :first_name, :last_name, :role, :rank, presence: true
#     validates :email, presence: true, uniqueness: true
#     validates :approved, inclusion: { in: [true] }, on: :scan

#     validate  :password_must_be_present_unless_invited
#     validate  :password_or_invitation_token_present
#   end

#   # Scopes
#   scope :active,  -> { where(status: :active) }
#   scope :invited, -> { where(status: :invited) }
#   scope :revoked, -> { where(status: :revoked) }
#   scope :approved, -> { where(approved: true) }

#   before_create :generate_invitation_token
#   after_create :warn_if_password_missing

#   def full_name
#     [first_name, middle_name&.first, last_name].compact.join(" ")
#   end

#   def invitation_token_present?
#     invitation_token.present? && invitation_accepted_at.nil?
#   end

#   def invitation_pending?
#     invited_at.present? && invitation_accepted_at.nil?
#   end

#   def should_validate_password?
#     invitation_accepted_at.present? || invitation_token.blank?
#   end

#   def officer?
#     role_int.in?([Officer.roles[:officer], Officer.roles[:director_general], Officer.roles[:inspector_general], Officer.roles[:agent]])
#   end

#   def admin?
#     role_int == Officer.roles[:admin]
#   end

#   def self.ransackable_attributes(_auth_object = nil)
#     %w[
#       id first_name last_name middle_name badge_id department_id
#       unit_type unit_name email phone_number status rank role
#       approved approved_at created_at updated_at
#     ]
#   end

#   def self.ransackable_associations(_auth_object = nil)
#     %w[department partner]
#   end

#   private

#   def generate_invitation_token
#     self.invitation_token ||= SecureRandom.hex(20)
#   end

#   def warn_if_password_missing
#     if encrypted_password.blank? && invitation_token.blank?
#       Rails.logger.warn("[SECURITY] Officer created without password or invite: #{email}")
#     end
#   end

#   def password_must_be_present_unless_invited
#     if encrypted_password.blank? && !invitation_pending?
#       errors.add(:password, "must be set unless sending an invitation")
#     end
#   end

#   def password_or_invitation_token_present
#     if encrypted_password.blank? && invitation_token.blank?
#       errors.add(:base, "Officer must have a password or an invitation token")
#     end
#   end

#   def updating_password?
#     password.present? || password_confirmation.present?
#   end
# end
