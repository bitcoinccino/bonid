# app/controllers/qr_scans_controller.rb
class QrScansController < ApplicationController
  # Public phone-camera scans must work without login
  before_action :authenticate_any_role!, except: [ :public_resolve ]

  # ============================================================
  # ENTRY POINTS
  # ============================================================

  # POST /qr/public_resolve
  def public_resolve
    resolve_internal(public_scan: true)
  end

  # POST /qr/resolve
  def resolve
    resolve_internal(public_scan: false)
  end

  # ============================================================
  # CORE RESOLUTION
  # ============================================================
  private

  def resolve_internal(public_scan:)
    payload = JSON.parse(params[:payload]) rescue nil
    return render_error("Invalid QR payload", :unprocessable_entity) unless payload.is_a?(Hash)

    schema = detect_schema(payload)
    return render_error("Unsupported QR schema", :unprocessable_entity) unless schema

    case schema
    when :bonid_v2
      handle_bonid_v2(payload, public_scan:)
    when :visitor_v1
      handle_visitor_v1(payload, public_scan:)
    when :legacy_partner_v1
      handle_legacy_partner_v1(payload)
    end
  end

  # ============================================================
  # SCHEMA DETECTION
  # ============================================================
  def detect_schema(payload)
    # BonID v2 — Ed25519 asymmetric signature (CURRENT)
    # {
    #   "v": 2, "iss": "bonid.ht", "typ": "BonID",
    #   "sub": "DV-1989-M-SE-P8697-1E8",
    #   "ts": 1710234567, "exp": 1741770567,
    #   "sig": "<base64url Ed25519>"
    # }
    if payload["v"].to_i == 2 &&
       payload["typ"] == "BonID" &&
       payload["sub"].present? &&
       payload["sig"].present?
      return :bonid_v2
    end

    # BonTouris Visitor QR (CURRENT)
    # {
    #   "v": 1,
    #   "type": "BonTourisID",
    #   "bonid": "...",
    #   "exp": "YYYY-MM-DD",
    #   "sig": "CHECKSUM"
    # }
    if payload["v"].to_i == 1 &&
       payload["type"] == "BonTourisID" &&
       payload["bonid"].present? &&
       payload["exp"].present? &&
       payload["sig"].present?
      return :visitor_v1
    end

    # Legacy partner QR (OLD — HMAC)
    if payload["bonid"].present? &&
       payload["expires_at"].present? &&
       payload["signature"].present?
      return :legacy_partner_v1
    end

    nil
  end

  # ============================================================
  # BONID v2 — Ed25519 ASYMMETRIC SIGNATURE
  # ============================================================
  def handle_bonid_v2(payload, public_scan:)
    result = BonidQrSigner.verify(payload)

    case result
    when :invalid_payload
      return render_error("Invalid QR payload", :unprocessable_entity)
    when :invalid_signature
      return render_error("Invalid QR signature", :unauthorized)
    when :expired
      return render_error("QR code expired", :unauthorized)
    end

    bonid = payload["sub"]
    submission = IdentitySubmission.find_by(bonid: bonid, status: :approved)
    return render_error("BonID not found", :not_found) unless submission
    return render_error("BonID expired", :unauthorized) if submission.expires_at&.past?

    log_qr_scan!(
      subject: submission,
      subject_type: "IdentitySubmission",
      partner: current_partner_if_verified,
      result: "valid"
    )

    # Verified partner → JSON response
    if current_partner_if_verified.present?
      return render json: {
        type: "BonID",
        version: 2,
        bonid: submission.bonid,
        status: "valid",
        verified_at: submission.verified_at,
        expires_at: submission.expires_at,
        message: "Valid BonID — Ed25519 verified"
      }, status: :ok
    end

    # Public scan → redirect to public verification page
    redirect_to verify_citizens_identity_submissions_path(
      verification_token: submission.verification_token
    )
  end

  # ============================================================
  # VISITOR / BONTOURIS QR (v1)
  # ============================================================
  def handle_visitor_v1(payload, public_scan:)
    bonid = payload["bonid"]
    exp   = payload["exp"]
    sig   = payload["sig"]

    # ---- Expiry check
    begin
      return render_error("QR code expired", :unauthorized) if Date.parse(exp) < Date.current
    rescue ArgumentError
      return render_error("Invalid expiration format", :unprocessable_entity)
    end

    # ---- Find visitor submission
    visitor = VisitorSubmission.find_by(bonid: bonid)
    return render_error("BonTouris ID not found", :not_found) unless visitor

    # ---- Signature check (OFFLINE CHECKSUM)
    expected = visitor.offline_checksum.to_s
    unless ActiveSupport::SecurityUtils.secure_compare(sig.to_s, expected)
      log_invalid_scan(visitor, "invalid_signature")
      return render_error("Invalid QR signature", :unauthorized)
    end

    # ---- Status gate
    unless visitor.approved?
      log_invalid_scan(visitor, "not_verified")
      return render_error("BonTouris ID not verified", :not_found)
    end

    # ---- Log scan (partner optional)
    log_qr_scan!(
      subject: visitor,
      subject_type: "VisitorSubmission",
      partner: current_partner_if_verified,
      result: "valid"
    )

    # ============================================================
    # RESPONSE BRANCHING
    # ============================================================

    # 🟩 VERIFIED PARTNER (stay inside dashboard)
    if current_partner_if_verified.present?
      render json: {
        type: "BonTourisID",
        bonid: visitor.bonid,
        status: "valid",
        expires_on: visitor.expires_at&.to_date,
        verification_code: visitor.offline_checksum,
        message: "Valid BonTouris ID"
      }, status: :ok
      return
    end

    # 🟦 PUBLIC SCAN (NO OTP, NO LOGIN)
    # Redirect to PUBLIC verification status page (NEW)
    redirect_to public_bon_touris_verify_path(
      bonid: visitor.bonid,
      exp: exp,
      sig: sig
    )
  end

  # ============================================================
  # LEGACY PARTNER QR (v1 — HMAC)
  # ============================================================
  def handle_legacy_partner_v1(payload)
    bonid        = payload["bonid"]
    expires_at_i = payload["expires_at"].to_i
    signature    = payload["signature"].to_s
    partner_slug = payload["partner"].to_s

    partner = Partner.find_by(slug: partner_slug)
    return render_error("Partner not verified", :forbidden) unless partner&.verified_at.present?

    return render_error("QR code expired", :unauthorized) if Time.at(expires_at_i) < Time.current

    secret   = Rails.application.credentials.dig(:bonid, :signature_secret)
    unsigned = payload.except("signature").to_json
    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, unsigned)

    unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)
      return render_error("Invalid QR signature", :unauthorized)
    end

    submission = IdentitySubmission.find_by(bonid: bonid)
    return render_error("BonID not found", :not_found) unless submission
    return render_error("BonID not verified", :not_found) unless submission.verified?

    log_qr_scan!(
      subject: submission,
      subject_type: "IdentitySubmission",
      partner: partner,
      result: "valid"
    )

    render json: {
      bonid: submission.bonid,
      verified_at: submission.verified_at,
      expires_at: submission.expires_at,
      partner: partner.name
    }, status: :ok
  end

  # ============================================================
  # LOGGING
  # ============================================================
  def log_qr_scan!(subject:, subject_type:, partner:, result:)
    PartnerAuditLog.create!(
      partner: partner,
      action: "qr_verification",
      metadata: {
        subject_type: subject_type,
        bonid: subject.bonid,
        result: result,
        source: partner.present? ? "partner_scan" : "public_scan",
        ip: request.remote_ip,
        user_agent: request.user_agent
      },
      occurred_at: Time.current
    ) if partner.present?
  end

  def log_invalid_scan(subject, reason)
    PartnerAuditLog.create!(
      partner: current_partner_if_verified,
      action: "qr_verification_failed",
      metadata: {
        bonid: subject.bonid,
        reason: reason,
        ip: request.remote_ip,
        user_agent: request.user_agent
      },
      occurred_at: Time.current
    ) if current_partner_if_verified
  end

  # ============================================================
  # HELPERS
  # ============================================================
  def current_partner_if_verified
    return nil unless current_partner
    return nil unless current_partner.verified_at.present?
    current_partner
  end

  def render_error(message, status)
    render json: { error: message }, status: status
  end
end
