# frozen_string_literal: true

module Citizens
  # Recognises the browser a citizen just signed in from and emails them when
  # it's one we haven't seen before.
  #
  # Each browser gets a random token in a permanent encrypted cookie; we store
  # only its digest per user. Same browser → silent. New browser → alert with a
  # "This wasn't me" link (see SessionRevocationsController).
  #
  # The very first device a citizen ever registers is recorded silently —
  # that's their signup / first login after this shipped, and alerting on it
  # would be noise.
  class DeviceRecognition
    COOKIE = :bonid_device
    REVOKE_LINK_TTL = 7.days

    def initialize(user:, request:, cookies:)
      @user    = user
      @request = request
      @cookies = cookies
    end

    def call
      token  = @cookies.encrypted[COOKIE].presence
      device = token && @user.known_devices.find_by(token_digest: KnownDevice.digest(token))

      if device
        device.update_columns(last_seen_at: Time.current, ip_address: @request.remote_ip,
                              updated_at: Time.current)
        return device
      end

      first_device = !@user.known_devices.exists?
      token  ||= SecureRandom.urlsafe_base64(32)
      geo      = (@request.location rescue nil)
      device   = @user.known_devices.create!(
        token_digest: KnownDevice.digest(token),
        user_agent:   @request.user_agent.to_s.first(500),
        ip_address:   @request.remote_ip,
        city:         geo&.city.presence,
        country:      geo&.country_code.presence,
        last_seen_at: Time.current
      )
      @cookies.permanent.encrypted[COOKIE] = {
        value: token, httponly: true, same_site: :lax,
        secure: Rails.application.config.force_ssl
      }

      unless first_device
        Citizens::CitizenMailer.with(
          user: @user, device: device, revoke_token: self.class.revoke_token(@user, device)
        ).new_device_login.deliver_later
      end

      device
    rescue => e
      # Never block a login over the alert.
      Rails.logger.error("[DeviceRecognition] #{e.class}: #{e.message}")
      nil
    end

    # Bound to the user's current session_version, so the link dies as soon as
    # any sign-out-everywhere happens (including clicking it once).
    def self.revoke_token(user, device)
      verifier.generate({ "u" => user.id, "d" => device.id, "v" => user.session_version },
                        expires_in: REVOKE_LINK_TTL, purpose: :revoke_sessions)
    end

    # → [user, device_id] or nil
    def self.resolve_revoke_token(token)
      data = verifier.verified(token.to_s, purpose: :revoke_sessions)
      return nil unless data.is_a?(Hash)

      user = User.find_by(id: data["u"])
      return nil unless user && user.session_version == data["v"]

      [ user, data["d"] ]
    end

    def self.verifier
      Rails.application.message_verifier(:citizen_revoke_sessions)
    end
  end
end
