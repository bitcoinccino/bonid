# frozen_string_literal: true

require "ed25519"
require "base64"

module BonTouris
  class Verifier
    REQUIRED_KEYS = %w[v iss sub iat exp typ sig].freeze

    def self.verify!(payload)
      return false unless valid_payload?(payload)
      return false if expired?(payload)

      verify_signature(payload)
    end

    def self.valid_payload?(payload)
      payload.is_a?(Hash) &&
        REQUIRED_KEYS.all? { |k| payload.key?(k) }
    end

    def self.expired?(payload)
      Date.parse(payload["exp"]) < Date.current
    rescue
      true
    end

    def self.verify_signature(payload)
      public_key = Ed25519::VerifyKey.new(
        Base64.decode64(ENV.fetch("BONID_ED25519_PUBLIC"))
      )

      canonical = %w[v iss sub iat exp typ]
        .map { |k| "#{k}=#{payload[k]}" }
        .join("\n")

      public_key.verify(
        Base64.urlsafe_decode64(payload["sig"]),
        canonical
      )

      true
    rescue Ed25519::VerifyError
      false
    end
  end
end
