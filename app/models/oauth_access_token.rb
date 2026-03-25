# frozen_string_literal: true

class OauthAccessToken < ApplicationRecord
  # ✅ Ensure the table name matches your DB naming (you already had this line)
  self.table_name = "o_auth_access_tokens"

  belongs_to :partner
  belongs_to :citizen, class_name: "User", optional: true

  validates :token, :expires_at, presence: true
  validates :scopes, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  before_validation :generate_token, on: :create
  before_create :generate_refresh_token

  # ------------------------------------------------------------
  # 🔐 Lifecycle States
  # ------------------------------------------------------------
  def expired?
    Time.current > expires_at
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def active?
    !revoked? && !expired?
  end

  # ------------------------------------------------------------
  # ♻️ Refresh Logic
  # ------------------------------------------------------------
  def refresh!
    raise "Token already revoked or expired" if revoked? || expired?

    new_token  = SecureRandom.hex(32)
    new_refresh = SecureRandom.hex(32)

    update!(
      token: new_token,
      refresh_token: new_refresh,
      expires_at: 1.hour.from_now
    )

    self
  end

  private

  def generate_token
    self.token ||= SecureRandom.hex(32)
  end

  def generate_refresh_token
    self.refresh_token ||= SecureRandom.hex(32)
  end
end
