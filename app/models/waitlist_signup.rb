# frozen_string_literal: true

class WaitlistSignup < ApplicationRecord
  belongs_to :commune, optional: true
  # Set when an "Organization" lead becomes a partner application.
  has_one :partner, dependent: :nullify

  # Referrals: people who signed up through this person's share link
  # (/enskri?ref=<referral_code>).
  belongs_to :referrer, class_name: "WaitlistSignup", foreign_key: :referred_by_code,
                        primary_key: :referral_code, optional: true, inverse_of: :referrals
  has_many :referrals, class_name: "WaitlistSignup", foreign_key: :referred_by_code,
                       primary_key: :referral_code, inverse_of: :referrer, dependent: :nullify

  validates :email, presence: true
  validates :email, uniqueness: { case_sensitive: false, message: "Imèl sa enskri deja" }
  validates :signup_type, inclusion: { in: %w[citizen business] }
  validates :locale, inclusion: { in: %w[en fr ht] }, allow_nil: true
  validates :organization_name, presence: true, if: :business?
  validates :sector, presence: true, if: :business?

  # US state/city (diaspora): state is a known code; city is free text
  # (picked from the suggestions or typed).
  validates :residence_state, inclusion: { in: ->(_) { DiasporaLocations.states.keys } }, allow_nil: true
  validates :residence_city, length: { maximum: 80 }, allow_nil: true
  # Citizens abroad: only countries open for signup (organizations keep any
  # country, it is their country of operation)
  validates :country_of_residence, inclusion: { in: DiasporaLocations::SIGNUP_COUNTRIES },
                                   on: %i[create signup_form], if: :citizen_abroad?

  # Public waitlist form only (save(context: :signup_form)): every field the
  # form shows must be filled. Messages follow the visitor's language.
  with_options on: :signup_form do
    # Same rule as the form's own check: something@domain.tld
    validates :email, format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, message: ->(*) { I18n.t("main.signup_form.error_email") } }
    validates :commune_id, presence: { message: ->(*) { I18n.t("main.signup_form.error_commune") } },
                           if: -> { citizen? && !diaspora? }
    validates :residence_state, presence: { message: ->(*) { I18n.t("main.signup_form.error_state") } }, if: :citizen_abroad?
    validates :residence_city, presence: { message: ->(*) { I18n.t("main.signup_form.error_city") } }, if: :citizen_abroad?
    validates :country_of_residence, presence: { message: ->(*) { I18n.t("main.signup_form.error_country") } },
                                     if: -> { business? && PartnerSectorConstants::COUNTRY_REQUIRED_SECTORS.include?(sector) }
    validates :unit_type, :unit_name, presence: { message: ->(*) { I18n.t("main.signup_form.error_unit") } },
                                      if: -> { business? && sector == "pnh" }
  end

  before_create :generate_referral_code
  before_validation :normalize_email, :normalize_residence, :normalize_referrer

  scope :citizens, -> { where(signup_type: "citizen") }
  scope :businesses, -> { where(signup_type: "business") }
  scope :diaspora_signups, -> { where(diaspora: true) }
  scope :waiting, -> { where(status: "waiting") }
  scope :invited, -> { where(status: "invited") }
  scope :converted, -> { where(status: "converted") }
  scope :by_commune, ->(commune_id) { where(commune_id: commune_id) }

  REFERRALS_COUNT_SQL = "(SELECT COUNT(*) FROM waitlist_signups refs " \
                        "WHERE refs.referred_by_code = waitlist_signups.referral_code)"

  # Adds a referrals_count attribute (admin list, sorting)
  scope :with_referrals_count, -> { select("waitlist_signups.*, #{REFERRALS_COUNT_SQL} AS referrals_count") }
  scope :min_referrals, ->(n) { where("#{REFERRALS_COUNT_SQL} >= ?", n) }
  scope :top_referrers_first, -> { order(Arel.sql("#{REFERRALS_COUNT_SQL} DESC"), created_at: :asc) }

  # Signup a share link points at (nil for an unknown code)
  def self.find_by_referral_code(code)
    normalized = code.to_s.upcase.strip
    normalized.present? ? find_by(referral_code: normalized) : nil
  end

  # "Miami, Florida" (nil outside the US state/city path)
  def residence_place
    state = DiasporaLocations.state_name(residence_state)
    [residence_city, state].compact_blank.join(", ").presence
  end

  # Language for this person's emails (Kreyòl for older rows without one)
  def email_locale
    locale.presence || "ht"
  end

  def citizen? = signup_type == "citizen"
  def business? = signup_type == "business"
  def citizen_abroad? = citizen? && diaspora?

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

  # Keep a referral only when the code belongs to someone else on the list;
  # an unknown or own code is dropped quietly (it never blocks a signup).
  def normalize_referrer
    return unless will_save_change_to_referred_by_code?
    return self.referred_by_code = nil if referred_by_code.blank?

    referrer = self.class.find_by_referral_code(referred_by_code)
    self.referred_by_code =
      if referrer && referrer.email != email && referrer.id != id then referrer.referral_code
      end
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
