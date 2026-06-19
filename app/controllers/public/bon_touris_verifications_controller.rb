# frozen_string_literal: true

require "ed25519"
require "base64"
require "json"

module Public
  class BonTourisVerificationsController < ApplicationController
    include BontourisPausable # v1 launch: paused unless BONTOURIS_ENABLED=true
    pause_bontouris_unless_enabled

    skip_before_action :authenticate_any_role!, raise: false
    layout "public"

    ISSUER = "bontouris.verifyem.ht"
    TYPE   = "BonTourisID"
    SCHEMA = 1

    # ==================================================
    # SHOW — ENTRY POINT FOR QR SCAN OR MANUAL ENTRY
    # ==================================================
    def show
      input_method = nil
      visitor      = nil

      if params[:payload].present?
        input_method = "qr_payload"
        decoded = decode_payload(params[:payload])
        return render_and_log_invalid("Invalid QR payload", input_method) unless decoded.is_a?(Hash)

        @result = verify_bon_touris(decoded)
        visitor = visitor_from_decoded(decoded)

      elsif params[:bon_touris_id].present?
        input_method = "manual"
        visitor = VisitorSubmission.find_by(bonid: params[:bon_touris_id].to_s.strip)
        @result = verify_manual(visitor)

      else
        return render_and_log_invalid("Missing QR payload", "unknown")
      end

      log_scan_event!(visitor: visitor, input_method: input_method, result: @result)

      render "public/bon_touris_verifications/show"
    end

    private

    # ----------------------------
    # Manual verification (server lookup)
    # ----------------------------
    def verify_manual(visitor)
      return fail_result(:unknown, "BonTouris ID not found.") unless visitor

      return fail_result(:expired, "This BonTouris ID has expired.") if visitor.expires_at.present? && visitor.expires_at < Time.current
      return fail_result(:not_verified, "This BonTouris ID is not approved.") unless visitor.approved?

      ok_result(visitor, verification_label: "Verified by server lookup (manual entry)")
    end

    # ----------------------------
    # Decode Base64 payload from QR
    # ----------------------------
    def decode_payload(encoded)
      json = Base64.urlsafe_decode64(encoded)
      JSON.parse(json)
    rescue StandardError
      nil
    end

    # ----------------------------
    # Main verification logic (Ed25519)
    # ----------------------------
    def verify_bon_touris(decoded)
      return fail_result(:invalid_payload, "Invalid payload version.") unless decoded["v"].to_i == SCHEMA
      return fail_result(:invalid_payload, "Invalid issuer.")          unless decoded["iss"] == ISSUER
      return fail_result(:invalid_payload, "Invalid document type.")   unless decoded["typ"] == TYPE

      bon_touris_id = decoded["sub"]
      signature     = decoded["sig"]

      return fail_result(:invalid_payload, "Missing identifier.") if bon_touris_id.blank?
      return fail_result(:invalid_payload, "Missing signature.")  if signature.blank?

      # expiration check (payload exp)
      if decoded["exp"].present?
        exp_i = decoded["exp"].to_i
        if exp_i > 0 && Time.at(exp_i) < Time.current
          return fail_result(:expired, "This BonTouris ID has expired.")
        end
      end

      visitor = VisitorSubmission.find_by(bonid: bon_touris_id)
      return fail_result(:unknown, "BonTouris ID not found.") unless visitor

      return fail_result(:invalid_signature, "Invalid cryptographic signature.") unless verify_signature(decoded)

      return fail_result(:not_verified, "This BonTouris ID is not approved.") unless visitor.approved?

      ok_result(visitor, decoded: decoded, verification_label: "Verified via Cryptographic Signature")
    end

    def visitor_from_decoded(decoded)
      id = decoded.is_a?(Hash) ? decoded["sub"] : nil
      return nil if id.blank?

      VisitorSubmission.find_by(bonid: id)
    end

    # ----------------------------
    # Ed25519 verification
    # ----------------------------
    def verify_signature(decoded)
      public_key = Ed25519::VerifyKey.new(
        Base64.decode64(ENV.fetch("BONID_ED25519_PUBLIC"))
      )

      canonical = %w[v iss sub iat exp typ]
        .map { |k| "#{k}=#{decoded[k]}" }
        .join("\n")

      public_key.verify(
        Base64.urlsafe_decode64(decoded["sig"]),
        canonical
      )

      true
    rescue Ed25519::VerifyError, ArgumentError, TypeError
      false
    end

    # ----------------------------
    # Logging
    # ----------------------------
    def log_scan_event!(visitor:, input_method:, result:)
      bon_touris_id = if visitor&.bonid.present?
                        visitor.bonid
      elsif params[:bon_touris_id].present?
                        params[:bon_touris_id].to_s.strip
      else
                        begin
                          decoded = decode_payload(params[:payload].to_s)
                          decoded.is_a?(Hash) ? decoded["sub"].to_s : "UNKNOWN"
                        rescue
                          "UNKNOWN"
                        end
      end

      actor = detect_actor

      attrs = {
        visitor_submission: visitor,
        bon_touris_id: bon_touris_id,
        input_method: input_method,
        ok: !!result[:ok],
        status: result[:status].to_s,
        message: result[:message].presence,
        actor_kind: actor[:kind],
        actor_label: actor[:label],
        actor_verified: actor[:verified],
        ip_address: request.remote_ip,
        user_agent: request.user_agent.to_s,
        accept_language: request.headers["Accept-Language"].to_s,
        referer: request.referer.to_s,
        request_id: request.request_id.to_s,
        occurred_at: Time.current
      }

      # Optional geo (nil-safe)
      if request.respond_to?(:location) && request.location
        attrs[:country] = request.location.country
        attrs[:region]  = request.location.region
        attrs[:city]    = request.location.city
      end

      VisitorScanEvent.create!(attrs)
    rescue => e
      Rails.logger.error("[BonTourisVerify] scan log failed: #{e.class} #{e.message}")
    end

    # Best-effort actor detection (works even if you don’t have partner auth wired yet)
    def detect_actor
      # If you have helpers like current_partner/current_partner_admin/current_officer/current_admin_user,
      # this will pick them up. Otherwise it defaults to public.
      if respond_to?(:current_partner) && current_partner
        { kind: "partner", label: "#{current_partner.name} (Partner)", verified: !!current_partner.respond_to?(:approved?) ? current_partner.approved? : true }
      elsif respond_to?(:current_partner_admin) && current_partner_admin
        { kind: "partner", label: "Partner Admin", verified: true }
      elsif respond_to?(:current_officer) && current_officer
        { kind: "officer", label: "Officer", verified: true }
      elsif respond_to?(:current_admin_user) && current_admin_user
        { kind: "admin", label: "Admin", verified: true }
      else
        { kind: "public", label: "Public", verified: false }
      end
    rescue
      { kind: "unknown", label: "Unknown", verified: false }
    end

    # ----------------------------
    # Result helpers
    # ----------------------------
    def ok_result(visitor, decoded: nil, verification_label:)
      {
        ok: true,
        status: :valid,
        headline: "✅ Identity Verified",
        verification_label: verification_label,
        type: TYPE,
        bon_touris_id: visitor.bonid,
        expires: visitor.expires_at || (decoded && decoded["exp"].present? ? Time.at(decoded["exp"].to_i) : nil),
        verification_code: (decoded && decoded["sig"].present?) ? decoded["sig"].to_s.first(8).upcase : visitor.bonid.to_s.last(8)
      }
    end

    def fail_result(status, message)
      {
        ok: false,
        status: status,
        headline: headline_for(status),
        message: message
      }
    end

    def render_and_log_invalid(message, input_method)
      @result = fail_result(:invalid_payload, message)
      log_scan_event!(visitor: nil, input_method: input_method, result: @result)
      render "public/bon_touris_verifications/show"
    end

    def headline_for(status)
      case status
      when :invalid_signature then "⚠️ Tampered / Invalid Signature"
      when :unknown           then "❌ Unknown BonTouris ID"
      when :not_verified      then "⏳ Not Yet Verified"
      when :expired           then "⌛ Expired"
      else "⚠️ Verification Failed"
      end
    end
  end
end
