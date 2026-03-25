# frozen_string_literal: true

require "bcrypt"

class OauthAuthorizationCode < ApplicationRecord
  belongs_to :oauth_application
  belongs_to :citizen, class_name: "User", foreign_key: :user_id

  before_validation :generate_code, on: :create
  before_validation :set_expiration, on: :create

  validates :code_digest, presence: true, uniqueness: true

  # Expose the plaintext code after creation (must be public)
  attr_reader :plain_code

  # === Methods ===
  def self.find_by_code(code)
    all.detect { |record| record.valid_code?(code) }
  end

  def valid_code?(code)
    !expired? && !used? && BCrypt::Password.new(code_digest).is_password?(code)
  end

  def expired?
    expires_at.present? && Time.current > expires_at
  end

  def used?
    used_at.present?
  end

  def mark_used!
    update!(used_at: Time.current)
  end

  private

  def generate_code
    plain_code = SecureRandom.hex(16)
    self.code_digest = BCrypt::Password.create(plain_code)
    @plain_code = plain_code
  end

  def set_expiration
    self.expires_at ||= 10.minutes.from_now
  end

end
