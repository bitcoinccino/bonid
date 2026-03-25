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

  before_validation :generate_code, on: :create, if: -> { code.blank? }
  before_validation :upcase_code

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
    abbr = commune_abbreviation
    self.code = "BONID-#{abbr}-#{SecureRandom.alphanumeric(4).upcase}"
  end

  def commune_abbreviation
    name = commune&.name&.strip
    return "HT" unless name.present?

    parts = name.gsub(/[^a-zA-ZÀ-ÿ\s-]/, "").split(/[\s-]+/)
    if parts.length >= 2
      parts.first(2).map { |p| p.first.upcase }.join
    else
      name.gsub(/[^a-zA-ZÀ-ÿ]/, "").first(2).upcase
    end
  end

  def upcase_code
    self.code = code&.upcase&.strip
  end
end
