# frozen_string_literal: true

require "bcrypt"

class OauthApplication < ApplicationRecord
  belongs_to :partner
  has_many :oauth_access_tokens, dependent: :destroy
  has_many :oauth_authorization_codes, dependent: :destroy

  before_create :generate_credentials

  validates :name, :redirect_uri, presence: true
  validates :uid, presence: true, uniqueness: true
  validates :secret_digest, presence: true

  # === Scopes ===
  scope :active, -> { where.not(uid: nil) }

  # === Methods ===
  def self.find_by_uid(uid)
    find_by(uid: uid)
  end

  def authenticate(secret)
    BCrypt::Password.new(secret_digest).is_password?(secret)
  end

  private

  def generate_credentials
    self.uid = SecureRandom.uuid
    self.secret_digest = BCrypt::Password.create(SecureRandom.hex(32))
  end
end
