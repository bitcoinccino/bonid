# frozen_string_literal: true

module Citizens
  class RegistrationsController < Devise::RegistrationsController
    layout "citizen_auth"

    # /signup opens on any of three green lights:
    #   ?partner=slug   verified partner (registers under that partner)
    #   ?commune=HT0112 launched commune (direct, partner_id stays nil)
    #   ?invite=CODE    available invite code (redeemed on account creation)
    # With none of them, the visitor goes to the waitlist form to pick
    # their commune there.
    before_action :load_partner, :load_signup_unlock
    helper_method :signup_unlocked?, :signup_context_params

    def new
      if signup_unlocked?
        super
      else
        redirect_to waitlist_path, alert: t("citizen_portal.auth.flash.join_waitlist")
      end
    end

    def create
      unless signup_unlocked?
        redirect_to waitlist_path, alert: t("citizen_portal.auth.flash.join_waitlist")
        return
      end

      # Detect existing verified user → route to sign-in instead of duplicate registration
      existing_email = params.dig(:citizen, :email)&.strip&.downcase
      if existing_email.present?
        existing_user = User.find_by("LOWER(email) = ?", existing_email)
        if existing_user
          store_partner_context_for_otp(@partner) if @partner

          if @partner && existing_user.identity_submissions.status_approved.exists?
            redirect_to login_path(from_partner: @partner.slug),
                        notice: t("citizen_portal.auth.flash.already_verified_partner", partner: @partner.name)
          else
            redirect_to login_path(from_partner: @partner&.slug),
                        notice: t("citizen_portal.auth.flash.have_account")
          end
          return
        end
      end

      super do |citizen|
        if citizen.persisted?
          # Assign citizen role
          citizen.add_role(:citizen) if citizen.respond_to?(:add_role)

          # Link to initiating partner (nil when a launched commune or a
          # partner-less invite code opened the gate)
          citizen.update(partner: @partner) if @partner

          # Invite codes count a use only once an account exists
          if @invite_code && !@invite_code.redeem!
            Rails.logger.warn("Invite code #{@invite_code.code} no longer available at sign-up")
          end

          # Waitlist entry (same email) → converted
          WaitlistSignup.convert_for!(citizen.email)

          # Generate OTP for immediate 2FA verification
          CitizenOtpService.new(citizen).generate!(ip: request.remote_ip)

          # Store pending consent context securely (partner sign-ups only)
          if @partner
            cookies.encrypted[:pending_consent] = {
              value: {
                partner_id: @partner.id,
                scopes: [ "identity" ],
                redirect_uri: citizens_dashboard_path
              }.to_json,
              expires: 15.minutes.from_now,
              httponly: true,
              secure: Rails.application.config.force_ssl,
              same_site: :strict
            }
          end

          # Optional: Log successful registration
          Rails.logger.info("New citizen registered: #{citizen.email} via #{signup_source}")
        end
      end
    end

    protected

    # Redirect to OTP verification after successful signup
    def after_sign_up_path_for(resource)
      citizens_verify_otp_path(
        email: resource.email,
        signup: "true",
        partner_slug: @partner&.slug
      )
    end

    private

    def load_partner
      slug = params[:partner].presence || params.dig(:citizen, :partner)
      @partner = Partner.find_by(slug: slug)
      @partner = nil unless @partner&.verified_at?
    end

    def load_signup_unlock
      @invite_code = InviteCode.find_available(params[:invite]) if params[:invite].present?

      # An invite issued for a verified partner signs the citizen up there
      invite_partner = @invite_code&.partner
      @partner ||= invite_partner if invite_partner&.verified_at?

      if params[:commune].present?
        @commune = Commune.find_by(code: params[:commune].to_s.upcase.strip)
        @commune = nil unless @commune&.launched?
      end
    end

    def signup_unlocked?
      @partner.present? || @commune.present? || @invite_code.present?
    end

    # Carried through the form so create sees the same green light as new
    def signup_context_params
      { partner: @partner&.slug, commune: @commune&.code, invite: @invite_code&.code }.compact
    end

    def signup_source
      if @partner then "partner #{@partner.slug}"
      elsif @invite_code then "invite #{@invite_code.code}"
      else "commune #{@commune.code}"
      end
    end

    # The homepage waitlist form, where a visitor picks their commune
    def waitlist_path
      enskri_path(lang: I18n.locale.to_s == "fr" ? "fr" : nil)
    end

    def build_resource(hash = {})
      super
      resource.skip_password = true
      # Start the portal in the language they signed up in (globe picker on
      # the sign-up page); otherwise the column default (Kreyòl) applies.
      resource.preferred_locale = I18n.locale.to_s if User::CITIZEN_LOCALES.include?(I18n.locale.to_s)
    end

    def sign_up_params
      params.require(:citizen).permit(:email, :phone)
    end

    # Preserve partner OAuth context so the OTP sign-in flow can
    # continue the OAuth handoff after authentication
    def store_partner_context_for_otp(partner)
      pending_data = {
        partner_id: partner.id,
        partner_slug: partner.slug,
        scopes: %w[openid profile email],
        redirect_uri: partner.primary_redirect_uri.presence || root_url,
        state: SecureRandom.urlsafe_base64(32),
        created_at: Time.current.to_i
      }

      session[:pending_consent] = pending_data
      session[:pending_partner_slug] = partner.slug

      cookies.encrypted[:pending_consent] = {
        value: pending_data.to_json,
        expires: 30.minutes.from_now,
        httponly: true,
        secure: Rails.application.config.force_ssl
      }
    end
  end
end
