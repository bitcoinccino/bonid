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
    NOTIFICATION_CHANNELS = %w[email phone].freeze

    def edit
      @citizen = current_citizen
    end

    def update
      @citizen = current_citizen
      attrs    = {}

      # Email change — mirrors the Ajan settings flow: lowercased, dedup'd
      # against other accounts, and only applied if it actually differs.
      if params.dig(:user, :email).present?
        new_email = params[:user][:email].to_s.strip.downcase
        if new_email != @citizen.email.to_s.downcase
          if User.where.not(id: @citizen.id).exists?(email: new_email)
            flash.now[:alert] = "Yon lòt kont itilize deja imel sa a."
            return render :edit, status: :unprocessable_entity
          end
          attrs[:email] = new_email
        end
      end

      if params.dig(:user, :preferred_locale).present?
        locale = params[:user][:preferred_locale].to_s
        attrs[:preferred_locale] = locale if SUPPORTED_LOCALES.include?(locale)
      end

      if params.dig(:user, :notification_channel).present?
        channel = params[:user][:notification_channel].to_s
        attrs[:notification_channel] = channel if NOTIFICATION_CHANNELS.include?(channel)
      end

      if attrs.empty?
        redirect_to citizens_settings_path, notice: "Pa gen chanjman."
        return
      end

      if @citizen.update(attrs)
        redirect_to citizens_settings_path, notice: "Paramèt yo sove."
      else
        flash.now[:alert] = @citizen.errors.full_messages.to_sentence.presence || "Pa kapab sove paramèt yo."
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
