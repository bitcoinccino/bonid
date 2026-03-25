# frozen_string_literal: true

class QrScanLogger
  VALID_SOURCES = %w[
    partner_scan
    officer_scan
    citizen_scan
    admin_scan
    public_scan
    unknown
  ].freeze

  # --------------------------------------------------
  # PUBLIC API
  # --------------------------------------------------
  def self.log!(submission:, request:, source:, officer: nil, partner: nil, admin: nil)
    normalized_source = normalize_source(source)
    ip = extract_ip(request)
    geo = lookup_geo(ip)

    ActiveRecord::Base.transaction do
      verifier =
        if officer
          officer.full_name.presence || "Officer"
        elsif partner
          partner.name.presence || "Partner"
        elsif admin
          admin.email.presence || "Admin"
        else
          "Public"
        end

      # --------------------------------------------------
      # LOW-LEVEL SCAN EVENT (raw scan)
      # --------------------------------------------------
      qr_scan = QrScan.create!(
        identity_submission: submission,
        scanned_at: Time.current,
        ip_address: ip,
        user_agent: request.user_agent,
        verified_by: verifier,
        partner: partner,
        officer: officer,
        country: geo[:country],
        city: geo[:city],
        region: geo[:region],
        organization: geo[:organization],
        manual: false
      )

      # --------------------------------------------------
      # AUDIT LOG (citizen / admin visible)
      # --------------------------------------------------
      scan_log = QrScanLog.create!(
        qr_scan: qr_scan,
        identity_submission: submission,
        partner: partner,
        officer: officer,
        ip_address: ip,
        user_agent: request.user_agent,
        scanned_at: Time.current,
        source: normalized_source,
        country: geo[:country],
        city: geo[:city],
        region: geo[:region],
        organization: geo[:organization]
      )

      # --------------------------------------------------
      # NOTIFY CITIZEN (ASYNC)
      # --------------------------------------------------
      Citizens::QrScanMailer.scan_alert(scan_log).deliver_later

      scan_log
    end
  rescue => e
    Rails.logger.error(
      "[QrScanLogger] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    )
    raise if Rails.env.development?
    nil
  end

  # ==================================================
  private
  # ==================================================

  def self.normalize_source(source)
    return "unknown" if source.blank?

    source = source.to_s
    VALID_SOURCES.include?(source) ? source : "unknown"
  end

  # --------------------------------------------------
  # Robust IP extraction (IPv4 + IPv6 + proxies)
  # --------------------------------------------------
  def self.extract_ip(request)
    request.headers["CF-Connecting-IP"] ||
      request.headers["X-Forwarded-For"]&.split(",")&.first ||
      request.remote_ip
  end

  # --------------------------------------------------
  # Safe IP → Geo lookup (NO request.location)
  # --------------------------------------------------
  def self.lookup_geo(ip)
    return empty_geo unless ip.present?

    result = Geocoder.search(ip).first
    return empty_geo unless result

    {
      country:      result.country,
      city:         result.city,
      region:       result.region,
      organization: result.try(:org)
    }
  rescue => e
    Rails.logger.info("[QrScanLogger] Geo lookup failed for #{ip}: #{e.message}")
    empty_geo
  end

  def self.empty_geo
    {
      country: nil,
      city: nil,
      region: nil,
      organization: nil
    }
  end
end
