# app/services/citizen_otp_service.rb
require "securerandom"
require "bcrypt"
require "digest"

class CitizenOtpService
  MAX_ATTEMPTS = 5
  COOLDOWN     = 30.seconds

  def initialize(user)
    # Normalize type
    if user.is_a?(CitizenProfile)
      @citizen_profile = user
      @user = user.user
    elsif user.is_a?(User)
      @user = user
      @citizen_profile = CitizenProfile.find_or_create_by!(user_id: user.id)
    else
      raise ArgumentError, "Expected User or CitizenProfile, got #{user.class.name}"
    end

    raise ArgumentError, "User must have an email" unless @user&.email.present?
  end

  # === Generate & Send OTP ===
  def generate!(fingerprint: nil, ip: nil, source: nil)
    enforce_cooldown!

    raw_otp = "%06d" % rand(0..999999)
    digest  = BCrypt::Password.create(raw_otp)
    expires = 10.minutes.from_now

    # 🧹 Cleanup expired/used sessions
    @citizen_profile.citizen_sessions
                    .where("expires_at < ? OR used_at IS NOT NULL", Time.current)
                    .delete_all

    # 💾 Create new session — safe in console or request
    @citizen_profile.citizen_sessions.create!(
      user_id: @user.id,
      otp_digest: digest,
      expires_at: expires,
      device_fingerprint: fingerprint.presence || "dev-console",
      login_source: source.presence || default_source,
      ip_address: ip.presence || default_ip
    )

    # 📩 Send email if user has one
    Citizens::CitizenMailer.with(user: @user, otp: raw_otp).otp_login.deliver_later if @user.email.present?

    raw_otp
  end

  # === Verify OTP ===
  def verify!(code, fingerprint: nil)
    session = latest_valid_session
    return false unless session

    # Optional fingerprint match
    if fingerprint && session.device_fingerprint.present? && session.device_fingerprint != fingerprint
      return false
    end

    # Brute-force protection
    attempts_key = "otp_attempts:#{session.id}"
    attempts = Rails.cache.increment(attempts_key, 1, expires_in: 10.minutes)
    return false if attempts && attempts > MAX_ATTEMPTS

    if BCrypt::Password.new(session.otp_digest) == code
      session.update!(used_at: Time.current)
      Rails.cache.delete(attempts_key)
      true
    else
      false
    end
  end

  private

  def latest_valid_session
    @citizen_profile.citizen_sessions
                    .where(used_at: nil)
                    .where("expires_at > ?", Time.current)
                    .order(created_at: :desc)
                    .first
  end

  def enforce_cooldown!
    last = @citizen_profile.citizen_sessions.order(created_at: :desc).first
    if last && last.created_at > COOLDOWN.ago
      raise StandardError, "Please wait a few seconds before requesting another code."
    end
  end

  # === Fallback values for console/testing ===
  def default_source
    Rails.env.development? || Rails.env.test? ? "dev_console" : "citizen_portal"
  end

  def default_ip
    Rails.env.development? || Rails.env.test? ? "127.0.0.1" : "0.0.0.0"
  end
end
