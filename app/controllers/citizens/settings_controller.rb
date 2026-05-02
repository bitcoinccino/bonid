# frozen_string_literal: true

# Citizens::SettingsController
# ============================
# Three-section settings page reachable from the topbar profile dropdown:
#   * Security        — change email; 2FA is a "coming soon" disabled card
#   * Language        — preferred_locale in %w[ht fr]
#   * Notifications   — notification_channel in %w[email phone]
#
# All updates flow through a single PATCH so the form can submit any
# combination of changes in one round-trip. 2FA is intentionally inert at
# this stage — the markup advertises the capability without backing it.
module Citizens
  class SettingsController < BaseController
    SUPPORTED_LOCALES = %w[ht fr].freeze
    # SMS is shelved until the SMS gateway lands — view disables it with a
    # K AP VINI badge, controller refuses it server-side as belt-and-braces.
    NOTIFICATION_CHANNELS = %w[email].freeze

    EMAIL_CHANGE_CACHE_TTL = 15.minutes
    EMAIL_CHANGE_MAX_ATTEMPTS = 5

    def edit
      @citizen = current_citizen
      load_pending_email_change_state
    end

    # POST /citizens/settings/email_change/cancel
    # Drops any in-flight email-change request so the citizen can edit the
    # destination email (typo, wrong account) without waiting for the
    # 15-min cache TTL. Re-renders the modal in Phase 1.
    def cancel_email_change
      Rails.cache.delete("email_change:#{current_citizen.id}")
      flash[:reopen_email_modal] = true
      redirect_to citizens_settings_path
    end

    def update
      @citizen = current_citizen

      # Apply non-email attrs immediately so locale/notification changes
      # don't get blocked behind an unverified email change.
      simple_attrs = collect_simple_attrs
      apply_simple_attrs!(simple_attrs)

      # Email change goes through a 6-digit code sent to the NEW address.
      requested_email = params.dig(:user, :email).to_s.strip.downcase
      code            = params.dig(:user, :email_change_code).to_s.strip

      if requested_email.present? && requested_email != @citizen.email.to_s.downcase
        return handle_email_change(requested_email, code)
      end

      # No email change in flight — honor the simple-attrs result.
      if simple_attrs.any?
        redirect_to citizens_settings_path, notice: "Paramèt yo sove."
      else
        redirect_to citizens_settings_path, notice: "Pa gen chanjman."
      end
    end

    private

    def collect_simple_attrs
      attrs = {}
      if params.dig(:user, :preferred_locale).present?
        locale = params[:user][:preferred_locale].to_s
        attrs[:preferred_locale] = locale if SUPPORTED_LOCALES.include?(locale)
      end
      if params.dig(:user, :notification_channel).present?
        channel = params[:user][:notification_channel].to_s
        attrs[:notification_channel] = channel if NOTIFICATION_CHANNELS.include?(channel)
      end
      attrs
    end

    def apply_simple_attrs!(attrs)
      return if attrs.empty?
      @citizen.update(attrs)
    end

    # Two-phase: first POST (no code) generates + emails the code; second
    # POST (with code) verifies and commits. State lives in Rails.cache
    # keyed by user_id so concurrent tabs/devices share it without a
    # schema change.
    def handle_email_change(new_email, code)
      if User.where.not(id: @citizen.id).exists?(email: new_email)
        flash.now[:alert] = "Yon lòt kont itilize deja imel sa a."
        @email_change_pending = false
        return render :edit, status: :unprocessable_entity
      end

      cache_key = email_change_cache_key
      pending   = Rails.cache.read(cache_key)

      if code.blank?
        # Phase 1 — issue and send a new code. Use deliver_now (not _later)
        # so a mailer/template error surfaces to the citizen immediately
        # instead of vanishing into the async worker — the citizen is
        # staring at the screen waiting for this.
        new_code = format("%06d", SecureRandom.random_number(1_000_000))
        Rails.cache.write(
          cache_key,
          { new_email: new_email, code: new_code, sent_at: Time.current.to_i, attempts: 0 },
          expires_in: EMAIL_CHANGE_CACHE_TTL
        )
        begin
          Citizens::CitizenMailer.with(user: @citizen, new_email: new_email, code: new_code)
                                 .email_change_verification.deliver_now
          Rails.logger.info "[Settings] Email-change code issued for user=#{@citizen.id} → #{new_email}"
        rescue StandardError => e
          Rails.logger.error "[Settings] Email-change mail failed for user=#{@citizen.id}: #{e.class} - #{e.message}"
          Rails.cache.delete(cache_key)
          flash.now[:alert] = "Pa kapab voye kòd verifikasyon an. Eseye ankò nan kèk minit."
          @email_change_pending = false
          return render :edit, status: :unprocessable_entity
        end

        @email_change_pending = true
        @pending_new_email    = new_email
        flash.now[:notice] = "Nou voye yon kòd nan #{new_email}. Antre l anba a pou konfime chanjman an."
        return render :edit, status: :ok
      end

      # Phase 2 — verify the code.
      if pending.blank? || pending[:new_email] != new_email
        flash.now[:alert] = "Kòd la ekspire oswa li pa pou imel sa a. Mande yon nouvo kòd."
        @email_change_pending = true
        @pending_new_email    = new_email
        return render :edit, status: :unprocessable_entity
      end

      if pending[:attempts].to_i >= EMAIL_CHANGE_MAX_ATTEMPTS
        Rails.cache.delete(cache_key)
        flash.now[:alert] = "Twòp esè. Mande yon nouvo kòd."
        @email_change_pending = false
        return render :edit, status: :unprocessable_entity
      end

      if pending[:code].to_s != code
        pending[:attempts] = pending[:attempts].to_i + 1
        Rails.cache.write(cache_key, pending, expires_in: EMAIL_CHANGE_CACHE_TTL)
        flash.now[:alert] = "Kòd la pa kòrèk. Eseye ankò."
        @email_change_pending = true
        @pending_new_email    = new_email
        return render :edit, status: :unprocessable_entity
      end

      if @citizen.update(email: new_email)
        Rails.cache.delete(cache_key)
        redirect_to citizens_settings_path, notice: "Imel ou chanje. Pwochen koneksyon, sèvi ak #{new_email}."
      else
        flash.now[:alert] = @citizen.errors.full_messages.to_sentence.presence || "Pa kapab sove imel la."
        @email_change_pending = true
        @pending_new_email    = new_email
        render :edit, status: :unprocessable_entity
      end
    end

    def load_pending_email_change_state
      pending = Rails.cache.read(email_change_cache_key)
      return unless pending && pending[:new_email].present?
      @email_change_pending  = true
      @pending_new_email     = pending[:new_email]
      # sent_at is stored as unix int — TTL is EMAIL_CHANGE_CACHE_TTL.
      @pending_expires_at    = pending[:sent_at].to_i + EMAIL_CHANGE_CACHE_TTL.to_i
    end

    def email_change_cache_key
      "email_change:#{current_citizen.id}"
    end
  end
end
