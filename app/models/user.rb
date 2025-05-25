# app/models/user.rb
require "openssl"

class User < ApplicationRecord
  # === Devise ===
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # === Associations ===
  has_one :officer
  has_one :address, as: :addressable, dependent: :destroy
  has_many :identity_submissions, dependent: :destroy
  accepts_nested_attributes_for :address

  # === Virtual Attributes ===
  attr_accessor :terms

  # === Validations ===
  validates :terms, acceptance: { accept: '1' }, on: :create

  # === Enums ===
  enum :role_int, {
    user: 0,
    admin: 1,
    partner_admin: 2,
    reviewer: 3
  }

  enum :sex, {
    M: 0,
    F: 1
  }

  enum :marital_status, {
    married: 0,
    divorced: 1,
    widowed: 2,
    single: 3,
    separated: 4,
    engaged: 5
  }

  enum :id_type, {
    cin: 0,
    passport: 1
  }

  # === Scopes ===
  scope :admins,    -> { where(role_int: :admin) }
  scope :reviewers, -> { where(role_int: :reviewer) }
  scope :partners,  -> { where(role_int: :partner_admin) }

  # === Role Check Methods ===
  def admin?         = role_int == "admin"
  def reviewer?      = role_int == "reviewer"
  def partner?       = role_int == "partner_admin"
  def officer?       = officer.present?

  # === Display ===
  def full_name
    [first_name, middle_name, last_name].compact.join(" ")
  end

  # === BONID ===
  def generate_bonid
    ln        = last_name.to_s[0..1].upcase.presence || "XX"
    year      = dob&.year.to_s || "XXXX"
    gender    = sex&.upcase || "U"
    dept      = address&.commune&.department&.name&.upcase&.delete(" ") || "UNKNOWN"
    id_prefix = id_type&.first&.upcase || "U"
    last4     = id_number.to_s[-4..] || "0000"

    "#{ln}-#{year}-#{gender}-#{dept}-#{id_prefix}-#{last4}"
  end

  def bonid
    @bonid ||= generate_bonid
  end

  def generate_qr_payload
    {
      bonid: bonid,
      signature: secure_bonid_signature
    }.to_json
  end

  private

  def secure_bonid_signature
    key = Rails.application.credentials.dig(:bonid, :signature_secret)
    OpenSSL::HMAC.hexdigest("SHA256", key, bonid.to_s)
  end

  def find_district_from_postal_code
    pc = address&.postal_code
    return "UNKNOWN" if pc.blank?

    case pc[2].to_i
    when 1 then "NORD"
    when 2 then "NORD-EST"
    when 3 then "NORD-OUEST"
    when 4 then "CENTRE"
    when 5 then "ARTIBONITE"
    when 6 then "OUEST"
    when 7 then "SUD-EST"
    when 8 then "SUD"
    when 9 then "GRAND'ANSE"
    else "UNKNOWN"
    end
  end
end
