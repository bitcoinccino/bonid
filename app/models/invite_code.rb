# frozen_string_literal: true

class InviteCode < ApplicationRecord
  belongs_to :partner, optional: true
  belongs_to :commune, optional: true
  belongs_to :user, optional: true

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :code_type, inclusion: { in: %w[personal partner community unlimited referral] }
  validates :max_uses, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :available, -> { active.not_expired.where("uses_count < max_uses OR max_uses IS NULL") }

  # Format: <PREFIX>-<TOKEN>, e.g. DEL-7KQ2XA. The token alphabet drops
  # characters people confuse when typing on a phone (0/O, 1/I/L).
  TOKEN_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ".chars.freeze
  TOKEN_LENGTH = 6
  NATIONAL_PREFIX = "HTI" # no commune (diaspora, national invites)

  before_validation :generate_code, on: :create, if: -> { code.blank? }
  before_validation :upcase_code

  # Forgiving input: "del 7kq2xa", "del7kq2xa" and "DEL-7KQ2XA" all match.
  def self.normalize(raw)
    cleaned = raw.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    return cleaned if cleaned.length <= TOKEN_LENGTH

    "#{cleaned[0...-TOKEN_LENGTH]}-#{cleaned[-TOKEN_LENGTH..]}"
  end

  # Usable code matching what the person typed (or nil). Also matches older
  # or hand-made codes stored in other shapes (BONID-PA-7KQ2, BONTEST1).
  def self.find_available(raw)
    return nil if raw.blank?

    candidates = [raw.to_s.upcase.strip, normalize(raw)].uniq
    available.where(code: candidates).first
  end

  # 3-letter prefix for a commune: its invite_prefix when set, else derived
  # from the name (Port-au-Prince → PAP, Delmas → DEL, Pétion-Ville → PVE).
  def self.prefix_for(commune)
    return NATIONAL_PREFIX if commune.nil?
    return commune.invite_prefix.upcase if commune.invite_prefix.present?

    words = I18n.transliterate(commune.name.to_s).upcase.scan(/[A-Z]+/)
    return NATIONAL_PREFIX if words.empty?

    initials = words.map(&:first).join
    initials = (initials + words.first[1..].to_s) if initials.length < 3
    initials.first(3).ljust(3, "X")
  end

  def valid_for_use?
    active? && !expired? && !exhausted?
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def exhausted?
    max_uses.present? && uses_count >= max_uses
  end

  def redeem!
    return false unless valid_for_use?
    increment!(:uses_count)
    true
  end

  def remaining_uses
    return nil if max_uses.nil? # unlimited
    [max_uses - uses_count, 0].max
  end

  private

  def generate_code
    prefix = self.class.prefix_for(commune)
    loop do
      token = Array.new(TOKEN_LENGTH) { TOKEN_ALPHABET[SecureRandom.random_number(TOKEN_ALPHABET.size)] }.join
      self.code = "#{prefix}-#{token}"
      break unless self.class.exists?(code: code)
    end
  end

  def upcase_code
    self.code = code&.upcase&.strip
  end
end
