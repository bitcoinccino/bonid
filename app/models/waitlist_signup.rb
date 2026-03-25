# frozen_string_literal: true

class WaitlistSignup < ApplicationRecord
  belongs_to :commune, optional: true

  validates :email, presence: true
  validates :email, uniqueness: { case_sensitive: false, message: "deja enskri" }
  validates :signup_type, inclusion: { in: %w[citizen business] }
  validates :organization_name, presence: true, if: -> { signup_type == "business" }
  validates :sector, presence: true, if: -> { signup_type == "business" }

  before_create :generate_referral_code
  before_validation :normalize_email

  scope :citizens, -> { where(signup_type: "citizen") }
  scope :businesses, -> { where(signup_type: "business") }
  scope :diaspora_signups, -> { where(diaspora: true) }
  scope :waiting, -> { where(status: "waiting") }
  scope :invited, -> { where(status: "invited") }
  scope :converted, -> { where(status: "converted") }
  scope :by_commune, ->(commune_id) { where(commune_id: commune_id) }

  def full_name
    "#{first_name} #{last_name}"
  end

  def mark_invited!
    update!(status: "invited", invited_at: Time.current)
  end

  def mark_converted!
    update!(status: "converted", converted_at: Time.current)
  end

  def commune_launched?
    commune&.launched?
  end

  private

  def generate_referral_code
    prefix = email&.first(2)&.upcase || "XX"
    self.referral_code = "#{prefix}-#{SecureRandom.alphanumeric(6).upcase}"
  end

  def normalize_email
    self.email = email&.downcase&.strip
  end
end
