# frozen_string_literal: true

require "bcrypt"

class TransactionConsentService
  class << self
    # ===========================================================
    # CREATE — Partner requests citizen consent for a transaction
    # ===========================================================
    def create_request!(partner:, citizen:, params:)
      raw_otp = generate_otp
      otp_digest = BCrypt::Password.create(raw_otp)

      channel = citizen.phone.present? ? "both" : "email"

      consent = TransactionConsent.create!(
        citizen: citizen,
        partner: partner,
        transaction_type: params[:transaction_type],
        scopes: Array(params[:scopes]).map(&:to_s),
        amount: params[:amount],
        currency: params[:currency] || "HTG",
        description: params[:description],
        reference_id: params[:reference_id],
        callback_url: params[:callback_url],
        otp_digest: otp_digest,
        notification_channel: channel,
        metadata: {
          ip: params[:ip],
          ua: params[:ua]
        }.compact
      )

      consent.append_audit!("created", transaction_type: params[:transaction_type])

      # Push real-time notification to citizen's browser via ActionCable
      Turbo::StreamsChannel.broadcast_prepend_to(
        "citizen_#{citizen.id}_consents",
        target: "pending-consents",
        partial: "citizens/transaction_consents/focus_card",
        locals: { consent: consent }
      )

      # Also broadcast a flash alert (visible on any citizen page, including dashboard)
      Turbo::StreamsChannel.broadcast_prepend_to(
        "citizen_#{citizen.id}_consents",
        target: "flash_messages",
        html: <<~HTML
          <div class="alert alert-warning alert-dismissible fade show d-flex align-items-center mx-3 mt-2" role="alert" style="z-index:1060;">
            <i class="ri-shield-keyhole-line ri-lg me-2"></i>
            <div>
              <strong>#{consent.partner.name}</strong> mande apwobasyon ou pou yon <strong>#{consent.transaction_type.titleize}</strong>.
              <a href="/citizens/transaction_consents" class="alert-link ms-1">Wè detay</a>
            </div>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
          </div>
        HTML
      )

      # Send email notification with OTP
      Citizens::TransactionConsentMailer
        .with(consent: consent, otp: raw_otp)
        .consent_request
        .deliver_later

      # Queue SMS (stubbed)
      if channel == "both"
        TransactionConsentSmsJob.perform_later(consent.id, raw_otp)
      end

      # Queue reminder in 2 minutes (requires async queue adapter)
      begin
        TransactionConsentReminderJob.set(wait: 2.minutes).perform_later(consent.id, raw_otp)
      rescue NotImplementedError
        Rails.logger.info("[TransactionConsentService] Reminder job skipped (no async adapter)")
      end

      consent
    end

    # ===========================================================
    # DECIDE — Citizen approves or denies with OTP
    # ===========================================================
    def verify_and_decide!(consent:, otp_code:, decision:, ip:)
      # Check expiry
      if consent.expires_at < Time.current
        consent.update!(status: :expired) if consent.pending?
        raise ExpiredError, "Consent has expired"
      end

      # Check OTP lockout
      if consent.otp_locked?
        raise LockedError, "Too many attempts. Request a new consent."
      end

      # Verify OTP
      unless consent.otp_valid?(otp_code)
        consent.increment_otp_attempts!
        remaining = TransactionConsent::MAX_OTP_ATTEMPTS - consent.otp_attempts
        raise InvalidOtpError, "Invalid code. #{remaining} attempt#{'s' if remaining != 1} remaining."
      end

      # Execute decision
      case decision.to_s.downcase
      when "approve"
        consent.approve!(ip: ip)
        Citizens::TransactionConsentMailer
          .with(consent: consent)
          .consent_approved
          .deliver_later
      when "deny"
        consent.deny!(ip: ip)
        Citizens::TransactionConsentMailer
          .with(consent: consent)
          .consent_denied
          .deliver_later
      else
        raise ArgumentError, "Invalid decision: must be 'approve' or 'deny'"
      end

      # Notify partner via webhook callback
      BonidNotifier.notify_transaction_consent(consent)

      consent
    end

    private

    def generate_otp
      SecureRandom.random_number(10**6).to_s.rjust(6, "0")
    end
  end

  # Custom errors
  class ExpiredError < StandardError; end
  class LockedError < StandardError; end
  class InvalidOtpError < StandardError; end
end
