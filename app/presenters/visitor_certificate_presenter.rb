# frozen_string_literal: true

require "ed25519"
require "base64"
require "json"
require "rqrcode"

class VisitorCertificatePresenter
  ISSUER = "bontouris.verifyem.ht"
  SCHEMA_VERSION = 1
  TYPE = "BonTourisID"

  def initialize(visitor)
    @visitor = visitor
  end

  # ==================================================
  # ID
  # ==================================================
  def bonid
    @visitor.bonid
  end

  # Masked for public display — hides PII segments
  # New (8 seg): T-DL-1988-M-US-P-885855-XDS → T-DL-••••-•-••-P-885855-XDS
  # Old (7 seg): T-DL-1988-M-US-P-885855     → T-DL-••••-•-••-P-885855
  def masked_bonid
    raw = @visitor.bonid.to_s
    segments = raw.split("-")

    if segments.size >= 8
      # New format with checksum: show first 2 + last 3, mask middle
      prefix = segments.first(2).join("-")
      masked = segments[2..-4].map { |s| "•" * s.length }.join("-")
      suffix = segments.last(3).join("-")
      "#{prefix}-#{masked}-#{suffix}"
    elsif segments.size >= 7
      # Legacy format without checksum: show first 2 + last 2, mask middle
      prefix = segments.first(2).join("-")
      masked = segments[2..-3].map { |s| "•" * s.length }.join("-")
      suffix = segments.last(2).join("-")
      "#{prefix}-#{masked}-#{suffix}"
    else
      raw
    end
  end

  # ==================================================
  # IDENTITY (DISPLAY ONLY)
  # ==================================================
  def full_name
    [
      @visitor.first_name,
      @visitor.middle_name,
      @visitor.last_name
    ].compact_blank.join(" ").presence || "Visitor"
  end

  def dob
    raw_dob&.strftime("%B %d, %Y") || "—"
  end

  def sex
    @visitor.sex.present? ? @visitor.sex.capitalize : "—"
  end

  def nationality
    @visitor.nationality.presence || "—"
  end

  # ==================================================
  # VISIT INFO (DISPLAY ONLY)
  # ==================================================
  def purpose
    @visitor.purpose_of_visit&.humanize || "—"
  end

  def entry_date
    date = @visitor.entry_date || @visitor.arrival_date || @visitor.created_at
    date ? date.strftime("%B %d, %Y") : "—"
  end

  def stay_duration
    days = @visitor.stay_duration_days
    return "—" unless days.present? && days.positive?

    days == 1 ? "1 day" : "#{days} days"
  end

  def valid_until
    raw_expiration&.strftime("%B %d, %Y") || "—"
  end

  # ==================================================
  # SECURITY (DISPLAY SAFE)
  #
  # New format (8 segments): HMAC checksum from the ID itself
  # Legacy (7 segments): Ed25519 signature truncation (fallback)
  # ==================================================
  def verification_code
    segments = @visitor.bonid.to_s.split("-")
    if segments.size >= 8
      segments.last.upcase
    else
      signature.to_s.first(8).upcase
    end
  end

  # ==================================================
  # QR — SIGNED PAYLOAD (PUBLIC VERIFY URL)
  #
  # Produces: /v?payload=<base64url(JSON)>
  # ==================================================
  def qr_payload
    encoded = Base64.urlsafe_encode64(qr_payload_hash.to_json, padding: false)

    Rails.application.routes.url_helpers.bon_touris_verify_url(
      payload: encoded,
      host: default_host
    )
  end

  def qr_svg
    return nil if qr_payload.blank?

    RQRCode::QRCode.new(qr_payload, level: :m).as_svg(
      offset: 10,
      color: "#000000",
      shape_rendering: "crispEdges",
      module_size: 5,
      standalone: true,
      viewbox: true
    )
  end

  # ==================================================
  # EXPIRATION HELPERS (FOR UI)
  # ==================================================
  def expiration_date
    raw_expiration
  end

  def days_until_expiration
    return nil unless raw_expiration

    (raw_expiration.to_date - Date.current).to_i
  end

  def expired?
    return false unless raw_expiration

    raw_expiration.to_date < Date.current
  end

  private

  # ==================================================
  # CRYPTO CORE
  # ==================================================
  def qr_payload_hash
    @qr_payload_hash ||= begin
      payload = unsigned_payload
      sig = signing_key.sign(canonical_string(payload))

      payload.merge(
        "sig" => Base64.urlsafe_encode64(sig, padding: false)
      )
    end
  end

  def unsigned_payload
    {
      "v"   => SCHEMA_VERSION,
      "iss" => ISSUER,
      "sub" => bonid,
      "iat" => issued_at,
      "exp" => expires_at,
      "typ" => TYPE
    }
  end

  # MUST match controller’s canonical builder:
  # %w[v iss sub iat exp typ].map { |k| "#{k}=#{decoded[k]}" }.join("\n")
  def canonical_string(payload)
    %w[v iss sub iat exp typ]
      .map { |k| "#{k}=#{payload[k]}" }
      .join("\n")
  end

  def signing_key
    @signing_key ||= Ed25519::SigningKey.new(
      Base64.decode64(ENV.fetch("BONID_ED25519_PRIVATE"))
    )
  end

  # ==================================================
  # RAW DATA
  # ==================================================
  def issued_at
    (@visitor.created_at || Time.current).to_i
  end

  def expires_at
    raw_expiration&.to_i
  end

  def raw_expiration
    @visitor.expires_at || 90.days.from_now
  end

  def raw_dob
    @visitor.respond_to?(:dob) ? @visitor.dob : @visitor.birth_date
  end

  # ==================================================
  # HOST
  # ==================================================
  def default_host
    Rails.application.routes.default_url_options[:host] ||
      ENV.fetch("APP_HOST", "http://localhost:3000")
  end

  def signature
    qr_payload_hash["sig"]
  end
end
