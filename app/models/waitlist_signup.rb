# frozen_string_literal: true

class WaitlistSignup < ApplicationRecord
  belongs_to :commune, optional: true
  # Set when an "Organization" lead becomes a partner application.
  has_one :partner, dependent: :nullify

  validates :email, presence: true
  validates :email, uniqueness: { case_sensitive: false, message: "Imèl sa enskri deja" }
  validates :signup_type, inclusion: { in: %w[citizen business] }
  validates :locale, inclusion: { in: %w[en fr ht] }, allow_nil: true

  # Language for this person's emails (Kreyòl for older rows without one)
  def email_locale
    locale.presence || "ht"
  end
  validates :organization_name, presence: true, if: -> { signup_type == "business" }
  validates :sector, presence: true, if: -> { signup_type == "business" }

  before_create :generate_referral_code
  before_validation :normalize_email, :normalize_residence

  # US state/city (diaspora): state is a known code; city is free text
  # (picked from the suggestions or typed).
  validates :residence_state, inclusion: { in: ->(_) { DiasporaLocations.states.keys } }, allow_nil: true
  validates :residence_city, length: { maximum: 80 }, allow_nil: true

  scope :citizens, -> { where(signup_type: "citizen") }
  scope :businesses, -> { where(signup_type: "business") }
  scope :diaspora_signups, -> { where(diaspora: true) }
  scope :waiting, -> { where(status: "waiting") }
  scope :invited, -> { where(status: "invited") }
  scope :converted, -> { where(status: "converted") }
  scope :by_commune, ->(commune_id) { where(commune_id: commune_id) }

  # "Miami, Florida" (nil outside the US state/city path)
  def residence_place
    state = DiasporaLocations.state_name(residence_state)
    [residence_city, state].compact_blank.join(", ").presence
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  def mark_invited!
    update!(status: "invited", invited_at: Time.current)
  end

  def mark_converted!
    update!(status: "converted", converted_at: Time.current)
  end

  # Called when a citizen account is created: any waitlist entry with the
  # same email becomes "converted" (admin metrics stay accurate without
  # manual updates). Also the hook for crediting referrals later.
  def self.convert_for!(email)
    normalized = email.to_s.downcase.strip
    return 0 if normalized.blank?
    where(email: normalized).where.not(status: "converted")
                            .update_all(status: "converted", converted_at: Time.current, updated_at: Time.current)
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

  # State/city only make sense for a US diaspora signup
  def normalize_residence
    if diaspora? && country_of_residence == DiasporaLocations::STATE_COUNTRY
      self.residence_state = residence_state.to_s.upcase.strip.presence
      self.residence_city = residence_city.to_s.squish.presence
      self.residence_city = nil if residence_state.nil?
    else
      self.residence_state = nil
      self.residence_city = nil
    end
  end
end
