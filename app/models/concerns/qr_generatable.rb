# app/models/concerns/qr_generatable.rb
module QrGeneratable
  extend ActiveSupport::Concern

  require "rqrcode"
  require "base64"

  included do
    def generate_qr_png_base64
      return qr_png_base64 if qr_png_base64.present?
      regenerate_combined_qr!
      qr_png_base64
    end

    def regenerate_combined_qr!
      raise "Missing verification token" if verification_token.blank?
      return unless user&.bonid.present?

      timestamp = Time.current.to_i
      secret_key = Rails.application.credentials.bonid_secret_key
      raise "Missing bonid_secret_key" unless secret_key

      signature = OpenSSL::HMAC.hexdigest("SHA256", secret_key, "bonid=#{user.bonid}timestamp=#{timestamp}")

      payload = {
        bonid: user.bonid,
        timestamp: timestamp,
        signature: signature,
        partner: partner&.slug
      }

      qr = RQRCode::QRCode.new(payload.to_json)
      png = qr.as_png(
        bit_depth: 1,
        border_modules: 4,
        color_mode: :rgb,
        color: verified? ? "#00209F" : "#6B7280",
        fill: verified? ? "#FFFFFF" : "#D1D5DB",
        module_px_size: 6,
        size: 240
      )

      update_column(:qr_png_base64, Base64.strict_encode64(png.to_s))
    end

    def qr_expired?
      return false unless qr_png_base64.present?
      decoded = Base64.decode64(qr_png_base64) rescue nil
      return true unless decoded

      begin
        payload = JSON.parse(RQRCode::QRCode.new(decoded).data)
        timestamp = payload["timestamp"].to_i
        (Time.current.to_i - timestamp) > 5.minutes.to_i
      rescue StandardError => e
        Rails.logger.error("Failed to check QR expiration: #{e.message}")
        true
      end
    end
  end
end
