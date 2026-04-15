# frozen_string_literal: true

class OneTimeSecret < ApplicationRecord
  belongs_to :partner

  validates :token, presence: true, uniqueness: true
  validates :encrypted_payload, presence: true
  validates :expires_at, presence: true

  before_validation :generate_token, on: :create

  scope :available, -> { where(viewed_at: nil).where("expires_at > ?", Time.current) }

  # Create a one-time secret link for sensitive credentials
  def self.create_for(partner:, payload:, label: nil, expires_in: 24.hours)
    create!(
      partner: partner,
      encrypted_payload: encrypt_payload(payload),
      label: label || "OAuth Credentials",
      expires_at: expires_in.from_now
    )
  end

  # Reveal the secret — marks it as viewed, returns the payload, then it's gone
  def reveal!(ip_address: nil)
    return nil if viewed? || expired?

    update!(viewed_at: Time.current, viewed_ip: ip_address)
    self.class.decrypt_payload(encrypted_payload)
  end

  def viewed?
    viewed_at.present?
  end

  def expired?
    expires_at < Time.current
  end

  def available?
    !viewed? && !expired?
  end

  def url
    Rails.application.routes.url_helpers.one_time_secret_url(
      token: token,
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  # AES-256-GCM encryption using Rails master key
  def self.encrypt_payload(data)
    encryptor = ActiveSupport::MessageEncryptor.new(encryption_key)
    encryptor.encrypt_and_sign(data.to_json)
  end

  def self.decrypt_payload(ciphertext)
    encryptor = ActiveSupport::MessageEncryptor.new(encryption_key)
    JSON.parse(encryptor.decrypt_and_verify(ciphertext))
  end

  def self.encryption_key
    Rails.application.credentials.secret_key_base[0..31]
  end
end
